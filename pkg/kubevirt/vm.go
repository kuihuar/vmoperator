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
	logger := log.FromContext(ctx)
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
					GPUs:       buildGPUs(vmp.Spec.GPUs),
				},
			},
			Networks: buildNetworks(networks),
			Volumes:  buildVolumes(volumes),
		},
	}

	// 如果指定了从快照恢复
	if vmp.Spec.RestoreFromSnapshot != "" {
		// 在实际实现中，这里需要根据快照名称找到对应的 VirtualMachineSnapshot
		// 并将其作为 VM 的数据源。KubeVirt 支持通过 VirtualMachineRestore 资源来实现。
		// 原型演示：记录日志并设置相关标志
		logger.Info("VM will be restored from snapshot", "snapshot", vmp.Spec.RestoreFromSnapshot)

	}

	// 添加 Cloud-Init 配置（如果有）
	// 注意：网络配置放在 userData 中，这是 Cloud-Init 的标准方式
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
// 支持两种模式：
// 1. 标准模式（默认）：Pod 网络作为主网络，Multus 网络作为次要网络（Secondary network）
// 2. Multus 作为主网络：当有网络标记为 Primary=true 且是 Multus 网络时，使用 Multus 作为主网络提供者
func buildNetworks(networks []vmv1alpha1.NetworkStatus) []kubevirtv1.Network {
	netList := make([]kubevirtv1.Network, 0, len(networks)+1)

	// 检查是否有标记为主网络的 Multus 网络
	var primaryMultusNetwork *vmv1alpha1.NetworkStatus
	for i := range networks {
		if networks[i].Primary && networks[i].NADName != "" {
			primaryMultusNetwork = &networks[i]
			break
		}
	}

	if primaryMultusNetwork == nil {
		// 标准模式：Pod 网络作为主网络（Default Kubernetes network）
		netList = append(netList, kubevirtv1.Network{
			Name: "default",
			NetworkSource: kubevirtv1.NetworkSource{
				Pod: &kubevirtv1.PodNetwork{},
			},
		})
	}

	// Multus 网络（次要网络或主网络）
	// 注意：Network 的 Name 必须与 Interface 的 Name 匹配（KubeVirt 要求）
	// NetworkName 用于引用 NetworkAttachmentDefinition
	for _, net := range networks {
		if net.NADName != "" {
			multusNet := &kubevirtv1.MultusNetwork{
				NetworkName: net.NADName, // NAD 名称用于 Multus 引用
			}
			// 如果这是主网络，设置 default: true（Multus as primary network provider）
			if net.Primary {
				multusNet.Default = true
			}
			netList = append(netList, kubevirtv1.Network{
				Name: net.Name, // 使用网络配置中的名称，与 Interface 匹配
				NetworkSource: kubevirtv1.NetworkSource{
					Multus: multusNet,
				},
			})
		}
	}

	return netList
}

// buildInterfaces 构建网络接口列表
// 每个接口必须引用一个 network 名称
// 支持两种模式：
// 1. 标准模式：Pod 网络接口（masquerade）作为主接口，Multus 网络接口（bridge）作为次要接口
// 2. Multus 作为主网络：Multus 网络接口作为主接口，不添加 Pod 网络接口
func buildInterfaces(networks []vmv1alpha1.NetworkStatus) []kubevirtv1.Interface {
	interfaceList := make([]kubevirtv1.Interface, 0, len(networks)+1)

	// 检查是否有标记为主网络的 Multus 网络
	hasPrimaryMultus := false
	for _, net := range networks {
		if net.Primary && net.NADName != "" {
			hasPrimaryMultus = true
			break
		}
	}

	if !hasPrimaryMultus {
		// 标准模式：Pod 网络接口作为主接口（Default Kubernetes network）
		interfaceList = append(interfaceList, kubevirtv1.Interface{
			Name: "default",
			InterfaceBindingMethod: kubevirtv1.InterfaceBindingMethod{
				Masquerade: &kubevirtv1.InterfaceMasquerade{},
			},
		})
	}

	// Multus 网络接口（次要网络或主网络）
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

// buildCloudInitData 构建 Cloud-Init 用户数据（包含网络配置）
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

	// 配置网络（如果有 IPConfig）
	networkConfig := buildCloudInitNetworkConfig(ctx, c, vmp, networks)
	if networkConfig != "" {
		cloudInit += networkConfig
	}

	return cloudInit
}

// buildCloudInitNetworkConfig 构建 Cloud-Init 网络配置（Netplan 格式）
// 仅支持 DHCP 模式
func buildCloudInitNetworkConfig(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus) string {
	logger := log.FromContext(ctx)

	// 创建网络名称到 NetworkStatus 的映射，以便获取 MAC 地址
	netStatusMap := make(map[string]vmv1alpha1.NetworkStatus)
	for _, netStatus := range networks {
		netStatusMap[netStatus.Name] = netStatus
	}

	var networkConfig strings.Builder
	headerWritten := false // 用于确保 network: 头部只写入一次
	multusInterfaceIndex := 1 // 用于跟踪 Multus 接口的索引（从 1 开始，因为 0 是 default）

	for _, net := range vmp.Spec.Networks {
		// 跳过 default 网络（它使用 Pod 网络，不需要配置）
		if net.Name == "default" {
			continue
		}

		// 只处理有 IPConfig 且模式为 DHCP 的网络
		if net.IPConfig == nil || net.IPConfig.Mode != "dhcp" {
			continue
		}

		// 检查是否有 NADName（Multus 网络必须有 NADName）
		netStatus, hasStatus := netStatusMap[net.Name]
		if hasStatus && netStatus.NADName == "" {
			// 如果没有 NADName，说明不是 Multus 网络，跳过
			continue
		}

		// 第一次遇到需要配置的网络时，写入 network: 头部
		if !headerWritten {
			networkConfig.WriteString("\nnetwork:\n")
			networkConfig.WriteString("  version: 2\n")
			networkConfig.WriteString("  ethernets:\n")
			headerWritten = true
		}

		// 对于 Multus 网络，尝试获取 MAC 地址和接口名称
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

		// 如果 NetworkStatus 中没有 MAC 地址，尝试从现有 VMI 获取
		if macAddress == "" && hasStatus {
			vmiName := fmt.Sprintf("%s-vm", vmp.Name)
			vmi := &kubevirtv1.VirtualMachineInstance{}
			key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmiName}
			if err := c.Get(ctx, key, vmi); err == nil {
				for _, iface := range vmi.Status.Interfaces {
					if iface.Name == net.Name {
						if iface.MAC != "" {
							macAddress = iface.MAC
						}
						break
					}
				}
			}
		}

		// 确定接口标识符
		if interfaceName == "" {
			interfaceName = fmt.Sprintf("eth%d", multusInterfaceIndex)
		}

		networkConfig.WriteString(fmt.Sprintf("    %s:\n", interfaceName))

		if macAddress != "" {
			// 使用 MAC 地址匹配（最可靠）
			networkConfig.WriteString("      match:\n")
			networkConfig.WriteString(fmt.Sprintf("        macaddress: %s\n", macAddress))
			networkConfig.WriteString(fmt.Sprintf("      set-name: %s\n", interfaceName))
		} else {
			// 如果没有 MAC 地址，尝试使用驱动程序或索引匹配（Netplan 允许）
			logger.V(1).Info("MAC address not available for network, using index-based matching", "network", net.Name, "interface", interfaceName)
			// 注意：在没有 MAC 的情况下，Netplan 很难精确匹配 Multus 接口
			// 这里我们依赖 KubeVirt 默认的接口顺序
		}

		// 启用 DHCP
		networkConfig.WriteString("      dhcp4: true\n")
		networkConfig.WriteString("      dhcp6: false\n")

		// 增加 Multus 接口索引
		multusInterfaceIndex++
	}

	return networkConfig.String()
}

// buildCloudInitNetworkData 构建 Cloud-Init 网络配置数据（使用 NetworkData 字段）
func buildCloudInitNetworkData(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong, networks []vmv1alpha1.NetworkStatus) string {
	logger := log.FromContext(ctx)

	// 创建网络名称到 NetworkStatus 的映射，以便获取 MAC 地址
	netStatusMap := make(map[string]vmv1alpha1.NetworkStatus)
	for _, netStatus := range networks {
		netStatusMap[netStatus.Name] = netStatus
	}

	hasNetworkConfig := false
	networkData := ""
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

			if !hasNetworkConfig {
				networkData += "network:\n"
				networkData += "  version: 2\n"
				networkData += "  ethernets:\n"
				hasNetworkConfig = true
			}

			// 对于 Multus 网络，尝试获取 MAC 地址和接口名称
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

			// 如果 NetworkStatus 中没有 MAC 地址，尝试从现有 VMI 获取
			// 注意：如果 hasStatus 为 false，说明是首次创建，VMI 可能还不存在
			if macAddress == "" && hasStatus {
				vmiName := fmt.Sprintf("%s-vm", vmp.Name)
				vmi := &kubevirtv1.VirtualMachineInstance{}
				key := client.ObjectKey{Namespace: vmp.Namespace, Name: vmiName}
				if err := c.Get(ctx, key, vmi); err == nil {
					for _, iface := range vmi.Status.Interfaces {
						if iface.Name == net.Name {
							if iface.MAC != "" {
								macAddress = iface.MAC
							}
							break
						}
					}
				}
			}

			// 生成网络配置
			if macAddress != "" {
				// 使用 MAC 地址匹配（最可靠）
				if interfaceName != "" {
					networkData += fmt.Sprintf("    %s:\n", interfaceName)
					networkData += fmt.Sprintf("      match:\n")
					networkData += fmt.Sprintf("        macaddress: %s\n", macAddress)
					networkData += fmt.Sprintf("      set-name: %s\n", interfaceName)
				} else {
					tempInterfaceName := fmt.Sprintf("eth%d", multusInterfaceIndex)
					networkData += fmt.Sprintf("    %s:\n", tempInterfaceName)
					networkData += fmt.Sprintf("      match:\n")
					networkData += fmt.Sprintf("        macaddress: %s\n", macAddress)
				}
			} else {
				logger.V(1).Info("MAC address not available for network, network configuration may not work correctly", "network", net.Name)
				if interfaceName == "" {
					interfaceName = fmt.Sprintf("eth%d", multusInterfaceIndex)
				}
				networkData += fmt.Sprintf("    %s:\n", interfaceName)
			}

			// 禁用 DHCP，使用静态 IP
			networkData += "      dhcp4: false\n"
			networkData += "      dhcp6: false\n"
			networkData += "      addresses:\n"
			networkData += fmt.Sprintf("        - %s\n", *net.IPConfig.Address)
			if net.IPConfig.Gateway != nil {
				networkData += fmt.Sprintf("      gateway4: %s\n", *net.IPConfig.Gateway)
			}
			if len(net.IPConfig.DNSServers) > 0 {
				networkData += "      nameservers:\n"
				networkData += "        addresses:\n"
				for _, dns := range net.IPConfig.DNSServers {
					networkData += fmt.Sprintf("          - %s\n", dns)
				}
			}

			// 增加 Multus 接口索引
			multusInterfaceIndex++
		}
	}

	return networkData
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

// buildGPUs 构建 GPU 设备列表
func buildGPUs(gpuConfigs []vmv1alpha1.GPUDevice) []kubevirtv1.GPU {
	gpus := make([]kubevirtv1.GPU, 0, len(gpuConfigs))
	for _, config := range gpuConfigs {
		gpus = append(gpus, kubevirtv1.GPU{
			Name:       config.Name,
			DeviceName: config.DeviceName,
		})
	}
	return gpus
}
