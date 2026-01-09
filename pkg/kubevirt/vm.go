package kubevirt

import (
	"context"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kubevirtv1 "kubevirt.io/api/core/v1"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// ReconcileVirtualMachine creates or updates a KubeVirt VirtualMachine
// based on the Wukong specification.
func ReconcileVirtualMachine(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus, volumes []vmv1alpha1.VolumeStatus) (string, error) {
	logger := log.FromContext(ctx)
	vmName := fmt.Sprintf("%s-vm", vmp.Name)

	logger.Info("Reconciling VirtualMachine", "name", vmName, "namespace", vmp.Namespace)

	// 构建 VirtualMachine 对象
	vm := buildVirtualMachine(ctx, c, vmp, networks, volumes)
	if vm == nil {
		return "", fmt.Errorf("failed to build VirtualMachine object")
	}

	// 尝试获取现有的 VirtualMachine
	existingVM := &kubevirtv1.VirtualMachine{}
	key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmName}
	if err := c.Get(ctx, key, existingVM); err != nil {
		if errors.IsNotFound(err) {
			// VirtualMachine 不存在，创建新的
			logger.Info("Creating VirtualMachine", "name", vmName)
			if err := c.Create(ctx, vm); err != nil {
				logger.Error(err, "failed to create VirtualMachine", "name", vmName)
				return "", err
			}
			return vmName, nil
		}
		// 其他错误
		logger.Error(err, "failed to get VirtualMachine", "name", vmName)
		return "", err
	}

	// VirtualMachine 已存在，更新它
	logger.V(1).Info("Found existing VirtualMachine, updating", "name", vmName)

	// 更新 spec
	if err := updateVMSpec(ctx, c, existingVM, vm, vmName, vmp.Namespace); err != nil {
		logger.Error(err, "failed to update VirtualMachine", "name", vmName)
		return "", err
	}

	return vmName, nil
}

// buildVirtualMachine 构建 VirtualMachine 对象
func buildVirtualMachine(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus, volumes []vmv1alpha1.VolumeStatus) *kubevirtv1.VirtualMachine {
	vmName := fmt.Sprintf("%s-vm", vmp.Name)

	vm := &kubevirtv1.VirtualMachine{
		ObjectMeta: metav1.ObjectMeta{
			Name:      vmName,
			Namespace: vmp.Namespace,
		},
		Spec: buildVMSpec(ctx, c, vmp, networks, volumes),
	}

	// 设置 OwnerReference，使 VM 成为 Wukong 的子资源
	if vmp.UID != "" {
		controller := true
		vm.OwnerReferences = []metav1.OwnerReference{
			{
				APIVersion: vmp.APIVersion,
				Kind:       vmp.Kind,
				Name:       vmp.Name,
				UID:        vmp.UID,
				Controller: &controller,
			},
		}
	}

	// 注意：对于 Multus 网络，KubeVirt 会根据 VM spec 中的 multus 配置自动处理
	// 不需要手动添加 k8s.v1.cni.cncf.io/networks annotation
	// KubeVirt 会自动在 Pod 上添加正确的 Multus annotation

	return vm
}

// buildVMSpec 构建 VirtualMachine spec
func buildVMSpec(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus, volumes []vmv1alpha1.VolumeStatus) kubevirtv1.VirtualMachineSpec {
	// 确定是否运行
	autoStart := true
	if vmp.Spec.StartStrategy != nil {
		autoStart = vmp.Spec.StartStrategy.AutoStart
	}

	// 解析内存
	memoryQuantity, err := resource.ParseQuantity(vmp.Spec.Memory)
	if err != nil {
		// 如果解析失败，使用默认值
		memoryQuantity = resource.MustParse("2Gi")
	}

	// 构建 template
	template := &kubevirtv1.VirtualMachineInstanceTemplateSpec{
		ObjectMeta: metav1.ObjectMeta{
			// 注意：KubeVirt 会自动处理 Multus 网络，不需要手动添加 annotation
			// 只需要在 networks 和 interfaces 中正确配置即可
		},
		Spec: kubevirtv1.VirtualMachineInstanceSpec{
			Domain: kubevirtv1.DomainSpec{
				CPU: &kubevirtv1.CPU{
					Cores: uint32(vmp.Spec.CPU),
				},
				Memory: &kubevirtv1.Memory{
					Guest: &memoryQuantity,
				},
				Devices: kubevirtv1.Devices{
					Disks:      buildDisks(volumes),
					Interfaces: buildInterfaces(networks),
				},
			},
			Networks: buildNetworks(networks),
			Volumes:  buildVolumes(volumes),
		},
	}

	// 添加 Cloud-Init 配置（如果有）
	if vmp.Spec.OSImage != "" || vmp.Spec.SSHKeySecret != "" || vmp.Spec.CloudInitUser != nil {
		cloudInitData := buildCloudInitData(ctx, c, vmp, networks)
		if cloudInitData != "" {
			// 添加 cloudInitNoCloud volume
			cloudInitVolume := kubevirtv1.Volume{
				Name: "cloudinitdisk",
				VolumeSource: kubevirtv1.VolumeSource{
					CloudInitNoCloud: &kubevirtv1.CloudInitNoCloudSource{
						UserData: cloudInitData,
					},
				},
			}
			template.Spec.Volumes = append(template.Spec.Volumes, cloudInitVolume)
		}
	}

	// 添加节点选择器和容忍度（如果有）
	// 注意：只有在明确配置 HighAvailability 时才设置，避免默认的调度约束
	if vmp.Spec.HighAvailability != nil {
		if len(vmp.Spec.HighAvailability.NodeSelector) > 0 {
			template.Spec.NodeSelector = vmp.Spec.HighAvailability.NodeSelector
		}
		if len(vmp.Spec.HighAvailability.Tolerations) > 0 {
			// 转换 tolerations
			tolerations := make([]corev1.Toleration, 0, len(vmp.Spec.HighAvailability.Tolerations))
			for _, tol := range vmp.Spec.HighAvailability.Tolerations {
				tolerations = append(tolerations, corev1.Toleration{
					Key:      tol.Key,
					Operator: corev1.TolerationOperator(tol.Operator),
					Value:    tol.Value,
					Effect:   corev1.TaintEffect(tol.Effect),
				})
			}
			template.Spec.Tolerations = tolerations
		}
	}
	// 确保如果没有配置，nodeSelector 为 nil（而不是空 map）
	// 这样可以避免意外的调度约束
	if template.Spec.NodeSelector != nil && len(template.Spec.NodeSelector) == 0 {
		template.Spec.NodeSelector = nil
	}

	spec := kubevirtv1.VirtualMachineSpec{
		Running:  &autoStart,
		Template: template,
	}

	return spec
}

// buildDisks 构建磁盘设备列表
func buildDisks(volumes []vmv1alpha1.VolumeStatus) []kubevirtv1.Disk {
	disks := make([]kubevirtv1.Disk, 0, len(volumes))
	for _, vol := range volumes {
		disk := kubevirtv1.Disk{
			Name: vol.Name,
			DiskDevice: kubevirtv1.DiskDevice{
				Disk: &kubevirtv1.DiskTarget{
					Bus: "virtio",
				},
			},
		}
		disks = append(disks, disk)
	}
	return disks
}

// buildNetworks 构建网络列表
func buildNetworks(networks []vmv1alpha1.NetworkStatus) []kubevirtv1.Network {
	netList := make([]kubevirtv1.Network, 0, len(networks)+1)

	// 默认网络（Pod 网络）
	netList = append(netList, kubevirtv1.Network{
		Name: "default",
		NetworkSource: kubevirtv1.NetworkSource{
			Pod: &kubevirtv1.PodNetwork{},
		},
	})

	// Multus 网络
	// 注意：Network 的 Name 必须与 Interface 的 Name 匹配（KubeVirt 要求）
	// NetworkName 用于引用 NetworkAttachmentDefinition
	for _, net := range networks {
		if net.NADName != "" {
			netList = append(netList, kubevirtv1.Network{
				Name: net.Name, // 使用网络配置中的名称，与 Interface 匹配
				NetworkSource: kubevirtv1.NetworkSource{
					Multus: &kubevirtv1.MultusNetwork{
						NetworkName: net.NADName, // NAD 名称用于 Multus 引用
					},
				},
			})
		}
	}

	return netList
}

// buildInterfaces 构建网络接口列表
// 每个接口必须引用一个 network 名称
func buildInterfaces(networks []vmv1alpha1.NetworkStatus) []kubevirtv1.Interface {
	interfaceList := make([]kubevirtv1.Interface, 0, len(networks)+1)

	// 默认网络接口（Pod 网络）
	interfaceList = append(interfaceList, kubevirtv1.Interface{
		Name: "default",
		InterfaceBindingMethod: kubevirtv1.InterfaceBindingMethod{
			Masquerade: &kubevirtv1.InterfaceMasquerade{},
		},
	})

	// Multus 网络接口
	// 注意：Interface 的 Name 必须与 Network 的 Name 匹配（KubeVirt 要求）
	for _, net := range networks {
		if net.NADName != "" {
			interfaceList = append(interfaceList, kubevirtv1.Interface{
				Name: net.Name, // 使用网络配置中的名称，与 Network 匹配
				InterfaceBindingMethod: kubevirtv1.InterfaceBindingMethod{
					Bridge: &kubevirtv1.InterfaceBridge{}, // 对于 bridge CNI 使用 Bridge binding
				},
			})
		}
	}

	return interfaceList
}

// buildVolumes 构建卷列表
func buildVolumes(volumes []vmv1alpha1.VolumeStatus) []kubevirtv1.Volume {
	volList := make([]kubevirtv1.Volume, 0, len(volumes))
	for _, vol := range volumes {
		volume := kubevirtv1.Volume{
			Name: vol.Name,
			VolumeSource: kubevirtv1.VolumeSource{
				PersistentVolumeClaim: &kubevirtv1.PersistentVolumeClaimVolumeSource{
					PersistentVolumeClaimVolumeSource: corev1.PersistentVolumeClaimVolumeSource{
						ClaimName: vol.PVCName,
					},
				},
			},
		}
		volList = append(volList, volume)
	}
	return volList
}

// buildCloudInitData 构建 Cloud-Init 用户数据
func buildCloudInitData(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus) string {
	logger := log.FromContext(ctx)
	cloudInit := "#cloud-config\n"

	// 配置用户（如果有）
	if vmp.Spec.CloudInitUser != nil {
		user := vmp.Spec.CloudInitUser
		cloudInit += "users:\n"
		cloudInit += fmt.Sprintf("  - name: %s\n", user.Name)

		// 配置密码
		if user.PasswordHash != "" {
			// 使用提供的密码哈希（推荐）
			cloudInit += fmt.Sprintf("    passwd: %s\n", user.PasswordHash)
		} else if user.Password != "" {
			// 使用明文密码（不推荐，可能不工作）
			// cloud-init 的 passwd 字段需要密码哈希格式（如 $6$...）
			// 生成密码哈希: echo -n "password" | openssl passwd -1 -stdin
			// 或: python3 -c "import crypt; print(crypt.crypt('password', crypt.mksalt(crypt.METHOD_SHA512)))"
			logger.Info("Using plain text password, cloud-init may not work correctly. Please use passwordHash instead", "user", user.Name)
			cloudInit += fmt.Sprintf("    passwd: %s\n", user.Password)
		}

		// 配置 sudo
		if user.Sudo != "" {
			cloudInit += fmt.Sprintf("    sudo: %s\n", user.Sudo)
		} else {
			cloudInit += "    sudo: ALL=(ALL) NOPASSWD:ALL\n"
		}

		// 配置 shell
		if user.Shell != "" {
			cloudInit += fmt.Sprintf("    shell: %s\n", user.Shell)
		} else {
			cloudInit += "    shell: /bin/bash\n"
		}

		// 配置 groups
		if len(user.Groups) > 0 {
			cloudInit += "    groups:\n"
			for _, group := range user.Groups {
				cloudInit += fmt.Sprintf("      - %s\n", group)
			}
		} else {
			// 默认 groups
			cloudInit += "    groups: sudo, adm, dialout, cdrom, floppy, audio, dip, video, plugdev, netdev\n"
		}

		// 配置 lock_passwd
		cloudInit += fmt.Sprintf("    lock_passwd: %v\n", user.LockPasswd)

		// 允许密码认证
		cloudInit += "\nssh_pwauth: true\n"
		cloudInit += "disable_root: false\n"
	}

	// 配置 SSH Key（如果有）
	if vmp.Spec.SSHKeySecret != "" {
		// 从 Secret 中读取 SSH 公钥
		secret := &corev1.Secret{}
		key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmp.Spec.SSHKeySecret}
		if err := c.Get(ctx, key, secret); err == nil {
			// 查找 SSH 公钥（通常在 'ssh-publickey' 或 'id_rsa.pub' key 中）
			var sshKey []byte
			for _, keyName := range []string{"ssh-publickey", "id_rsa.pub", "authorized_keys", "publickey"} {
				if val, ok := secret.Data[keyName]; ok {
					sshKey = val
					break
				}
			}
			// 如果没找到，尝试第一个非空值
			if len(sshKey) == 0 {
				for _, val := range secret.Data {
					if len(val) > 0 {
						sshKey = val
						break
					}
				}
			}
			if len(sshKey) > 0 {
				cloudInit += "\nssh_authorized_keys:\n"
				// 按行分割 SSH 公钥
				keys := strings.Split(string(sshKey), "\n")
				for _, key := range keys {
					key = strings.TrimSpace(key)
					if key != "" && !strings.HasPrefix(key, "#") {
						cloudInit += fmt.Sprintf("  - %s\n", key)
					}
				}
			} else {
				logger.V(1).Info("SSH key not found in Secret", "secret", vmp.Spec.SSHKeySecret)
			}
		} else {
			logger.V(1).Info("Failed to get SSH key Secret", "secret", vmp.Spec.SSHKeySecret, "error", err)
		}
	}

	// 配置网络（如果有静态 IP）
	// 创建网络名称到 NetworkStatus 的映射，以便获取 MAC 地址
	netStatusMap := make(map[string]vmv1alpha1.NetworkStatus)
	for _, netStatus := range networks {
		netStatusMap[netStatus.Name] = netStatus
	}

	hasNetworkConfig := false
	multusInterfaceIndex := 1 // 用于跟踪 Multus 接口的索引（从 1 开始，因为 0 是 default）
	for _, net := range vmp.Spec.Networks {
		if net.IPConfig != nil && net.IPConfig.Mode == "static" && net.IPConfig.Address != nil {
			// 跳过 default 网络（它使用 Pod 网络，不需要静态 IP 配置）
			if net.Name == "default" {
				continue
			}

			// 检查是否有 NADName（Multus 网络必须有 NADName）
			netStatus, hasStatus := netStatusMap[net.Name]
			if hasStatus && netStatus.NADName == "" {
				// 如果没有 NADName，说明不是 Multus 网络，跳过
				continue
			}

			// 如果没有 netStatus，但网络配置了静态 IP，也尝试生成配置
			// 这可能是首次创建时的情况

			if !hasNetworkConfig {
				cloudInit += "\nnetwork:\n"
				cloudInit += "  version: 2\n"
				cloudInit += "  renderer: networkd\n" // 使用 networkd renderer，更可靠
				cloudInit += "  ethernets:\n"
				hasNetworkConfig = true
			}

			// 对于 Multus 网络，尝试获取 MAC 地址和接口名称
			// MAC 地址匹配是最可靠的方式，适用于所有 Linux 发行版和不同的接口命名规则
			macAddress := ""
			interfaceName := ""

			// 优先使用 NetworkStatus 中的信息
			if hasStatus {
				if netStatus.MACAddress != "" {
					macAddress = netStatus.MACAddress
				}
				if netStatus.Interface != "" {
					interfaceName = netStatus.Interface
				}
			}

			// 如果 NetworkStatus 中没有 MAC 地址或接口名称，尝试从现有 VMI 获取
			if (macAddress == "" || interfaceName == "") && hasStatus && netStatus.NADName != "" {
				vmiName := fmt.Sprintf("%s-vm", vmp.Name)
				vmi := &kubevirtv1.VirtualMachineInstance{}
				key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmiName}
				if err := c.Get(ctx, key, vmi); err == nil {
					// 查找对应的接口 MAC 地址和接口名称
					// 注意：VMI 接口的 Name 是网络名称（net.Name），不是 NAD 名称
					for _, iface := range vmi.Status.Interfaces {
						if iface.Name == net.Name {
							if macAddress == "" && iface.MAC != "" {
								macAddress = iface.MAC
							}
							// 注意：VMI 中的接口名称可能不是 VM 内部的接口名称
							// 但我们可以尝试使用 podInterfaceName 或其他信息
							break
						}
					}
				}
			}

			// 生成网络配置
			// 最佳实践：优先使用 MAC 地址匹配，不依赖硬编码的接口名称
			if macAddress != "" {
				// 使用 MAC 地址匹配（最可靠，适用于所有 Linux 发行版）
				// 如果 NetworkStatus 中有接口名称，使用它；否则让 Netplan 自动检测
				if interfaceName != "" {
					// 使用 NetworkStatus 中提供的接口名称
					cloudInit += fmt.Sprintf("    %s:\n", interfaceName)
					cloudInit += fmt.Sprintf("      match:\n")
					cloudInit += fmt.Sprintf("        macaddress: %s\n", macAddress)
					cloudInit += fmt.Sprintf("      set-name: %s\n", interfaceName)
				} else {
					// 只使用 MAC 地址匹配，不设置接口名称（让系统自动分配）
					// 使用一个临时名称作为配置键，Netplan 会根据 MAC 地址匹配到实际接口
					tempInterfaceName := fmt.Sprintf("eth%d", multusInterfaceIndex)
					cloudInit += fmt.Sprintf("    %s:\n", tempInterfaceName)
					cloudInit += fmt.Sprintf("      match:\n")
					cloudInit += fmt.Sprintf("        macaddress: %s\n", macAddress)
					// 不设置 set-name，让系统使用默认的接口名称（enp2s0, eth1, ens3 等）
				}
			} else {
				// 如果没有 MAC 地址，这是一个警告情况
				// 这种情况下，我们无法可靠地配置网络，因为接口名称在不同系统上可能不同
				logger.V(1).Info("MAC address not available for network, network configuration may not work correctly", "network", net.Name)
				// 如果 NetworkStatus 中有接口名称，使用它；否则使用通用名称（可能不工作）
				if interfaceName == "" {
					interfaceName = fmt.Sprintf("eth%d", multusInterfaceIndex)
				}
				cloudInit += fmt.Sprintf("    %s:\n", interfaceName)
			}

			// 禁用 DHCP，使用静态 IP
			cloudInit += "      dhcp4: false\n"
			cloudInit += "      dhcp6: false\n"
			// 添加 addresses 配置
			cloudInit += "      addresses:\n"
			cloudInit += fmt.Sprintf("        - %s\n", *net.IPConfig.Address)
			if net.IPConfig.Gateway != nil {
				cloudInit += fmt.Sprintf("      gateway4: %s\n", *net.IPConfig.Gateway)
			}
			if len(net.IPConfig.DNSServers) > 0 {
				cloudInit += "      nameservers:\n"
				cloudInit += "        addresses:\n"
				for _, dns := range net.IPConfig.DNSServers {
					cloudInit += fmt.Sprintf("          - %s\n", dns)
				}
			}

			// 增加 Multus 接口索引
			multusInterfaceIndex++
		}
	}

	return cloudInit
}

// updateVMSpec 更新现有 VirtualMachine 的 spec
func updateVMSpec(ctx context.Context, c client.Client, existingVM, newVM *kubevirtv1.VirtualMachine, vmName, namespace string) error {
	logger := log.FromContext(ctx)

	// 更新 spec
	existingVM.Spec = newVM.Spec

	// 更新 annotations
	if len(newVM.Annotations) > 0 {
		if existingVM.Annotations == nil {
			existingVM.Annotations = make(map[string]string)
		}
		for k, v := range newVM.Annotations {
			existingVM.Annotations[k] = v
		}
	}

	// 应用更新
	if err := c.Update(ctx, existingVM); err != nil {
		logger.Error(err, "failed to update VirtualMachine", "name", vmName)
		return err
	}

	logger.Info("Successfully updated VirtualMachine", "name", vmName)
	return nil
}

// GetVMStatus 获取 VirtualMachine 的状态信息
func GetVMStatus(ctx context.Context, c client.Client, namespace, vmName string) (string, string, error) {
	logger := log.FromContext(ctx)

	vm := &kubevirtv1.VirtualMachine{}
	key := client.ObjectKey{Namespace: namespace, Name: vmName}
	if err := c.Get(ctx, key, vm); err != nil {
		if errors.IsNotFound(err) {
			return "", "", nil
		}
		return "", "", err
	}

	// 获取 VMI（VirtualMachineInstance）状态
	vmiName := vmName
	vmi := &kubevirtv1.VirtualMachineInstance{}
	vmiKey := client.ObjectKey{Namespace: namespace, Name: vmiName}
	if err := c.Get(ctx, vmiKey, vmi); err != nil {
		if errors.IsNotFound(err) {
			// VMI 不存在，VM 可能未启动
			return "Stopped", "", nil
		}
		logger.V(1).Info("VMI not found, VM may be stopped", "name", vmiName)
		return "Stopped", "", nil
	}

	// 获取 phase
	phase := string(vmi.Status.Phase)
	if phase == "" {
		phase = "Unknown"
	}

	// 获取 nodeName
	nodeName := vmi.Status.NodeName

	return phase, nodeName, nil
}
