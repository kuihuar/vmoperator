package kubevirt

import (
	"context"
	"encoding/json"
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

	// 构建 annotations（用于 Multus 网络）
	annotations := buildNetworkAnnotations(networks)
	if len(annotations) > 0 {
		vm.Annotations = annotations
	}

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
			Annotations: buildNetworkAnnotations(networks),
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
		cloudInitData := buildCloudInitData(ctx, c, vmp)
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

	// 在开发环境（单节点）中，如果没有配置 tolerations，添加默认的 toleration
	// 允许在 control-plane 节点上调度（仅当没有配置 HighAvailability 时）
	if vmp.Spec.HighAvailability == nil || len(vmp.Spec.HighAvailability.Tolerations) == 0 {
		// 添加容忍 control-plane taint（如果存在）
		// 注意：虽然节点没有 taint，但某些 KubeVirt 配置可能要求这个
		// 这里先不添加，因为节点确实没有 taint
		// 如果问题仍然存在，可能需要检查 KubeVirt 的配置
	}

	spec := kubevirtv1.VirtualMachineSpec{
		Running:  &autoStart,
		Template: template,
	}

	return spec
}

// buildNetworkAnnotations 构建 Multus 网络注解
func buildNetworkAnnotations(networks []vmv1alpha1.NetworkStatus) map[string]string {
	if len(networks) == 0 {
		return nil
	}

	annotations := make(map[string]string)
	netList := make([]map[string]string, 0, len(networks))

	for i, net := range networks {
		if net.NADName != "" {
			netList = append(netList, map[string]string{
				"name":      net.NADName,
				"interface": fmt.Sprintf("net%d", i+1),
			})
		}
	}

	if len(netList) > 0 {
		netJSON, err := json.Marshal(netList)
		if err == nil {
			annotations["k8s.v1.cni.cncf.io/networks"] = string(netJSON)
		}
	}

	return annotations
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
	for _, net := range networks {
		if net.NADName != "" {
			netList = append(netList, kubevirtv1.Network{
				Name: net.NADName,
				NetworkSource: kubevirtv1.NetworkSource{
					Multus: &kubevirtv1.MultusNetwork{
						NetworkName: net.NADName,
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
	for i, net := range networks {
		if net.NADName != "" {
			interfaceList = append(interfaceList, kubevirtv1.Interface{
				Name: net.NADName,
				InterfaceBindingMethod: kubevirtv1.InterfaceBindingMethod{
					Bridge: &kubevirtv1.InterfaceBridge{},
				},
			})
			// 如果这是第一个 Multus 网络，也可以使用 SR-IOV 或其他类型
			_ = i // 占位，后续可以根据配置选择不同的接口类型
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
func buildCloudInitData(ctx context.Context, c client.Client, vmp *vmv1alpha1.Wukong) string {
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
			// 使用明文密码（不推荐）
			// 注意：cloud-init 的 passwd 字段需要密码哈希格式（如 $6$...）
			// 明文密码可能不会工作，强烈建议使用 passwordHash
			// 生成密码哈希: echo -n "password" | openssl passwd -1 -stdin
			// 或: python3 -c "import crypt; print(crypt.crypt('password', crypt.mksalt(crypt.METHOD_SHA512)))"
			logger.Info("Using plain text password, cloud-init may not work correctly. Please use passwordHash instead", "user", user.Name)
			// 尝试使用明文（某些 cloud-init 版本可能支持，但不保证）
			// 如果密码无法工作，请使用 passwordHash
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
	hasNetworkConfig := false
	for _, net := range vmp.Spec.Networks {
		if net.IPConfig != nil && net.IPConfig.Mode == "static" && net.IPConfig.Address != nil {
			if !hasNetworkConfig {
				cloudInit += "\nnetwork:\n"
				cloudInit += "  version: 2\n"
				cloudInit += "  ethernets:\n"
				hasNetworkConfig = true
			}
			cloudInit += fmt.Sprintf("    %s:\n", net.Name)
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
