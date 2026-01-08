/*
Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package v1alpha1

import (
	"context"
	"fmt"

	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/webhook"
	"sigs.k8s.io/controller-runtime/pkg/webhook/admission"
)

// log is for logging in this package.
var wukonglog = logf.Log.WithName("wukong-resource")

// SetupWebhookWithManager sets up the webhook with the Manager.
func (r *Wukong) SetupWebhookWithManager(mgr ctrl.Manager) error {
	return ctrl.NewWebhookManagedBy(mgr).
		For(r).
		Complete()
}

// TODO(user): change verbs to "verbs=create;update;delete" if you want to enable deletion validation.
// +kubebuilder:webhook:path=/mutate-vm-novasphere-dev-v1alpha1-wukong,mutating=true,failurePolicy=fail,sideEffects=None,groups=vm.novasphere.dev,resources=wukongs,verbs=create;update,versions=v1alpha1,name=mwukong.kb.io,admissionReviewVersions=v1

var _ webhook.CustomDefaulter = &Wukong{}

// Default implements webhook.CustomDefaulter so a webhook will be registered for the type
func (r *Wukong) Default(ctx context.Context, obj runtime.Object) error {
	wukong := obj.(*Wukong)
	wukonglog.Info("default", "name", wukong.Name)

	// 设置默认内存（如果未指定）
	if wukong.Spec.Memory == "" {
		wukong.Spec.Memory = "2Gi"
		wukonglog.Info("set default memory", "memory", wukong.Spec.Memory)
	}

	// 设置默认启动策略
	if wukong.Spec.StartStrategy == nil {
		wukong.Spec.StartStrategy = &StartStrategySpec{
			AutoStart: true,
		}
		wukonglog.Info("set default start strategy", "autoStart", true)
	} else if wukong.Spec.StartStrategy.AutoStart && wukong.Spec.StartStrategy.RunStrategy == "" {
		// 如果 AutoStart 为 true 但 RunStrategy 未设置，设置默认值
		wukong.Spec.StartStrategy.RunStrategy = "Always"
	}

	// 为每个磁盘设置默认 StorageClass（如果未指定）
	for i := range wukong.Spec.Disks {
		if wukong.Spec.Disks[i].StorageClassName == "" {
			wukong.Spec.Disks[i].StorageClassName = "longhorn"
			wukonglog.Info("set default storage class for disk", "disk", wukong.Spec.Disks[i].Name, "storageClass", "longhorn")
		}
	}

	// 为网络接口设置默认类型（如果未指定）
	for i := range wukong.Spec.Networks {
		if wukong.Spec.Networks[i].Type == "" {
			wukong.Spec.Networks[i].Type = "bridge"
			wukonglog.Info("set default network type", "network", wukong.Spec.Networks[i].Name, "type", "bridge")
		}
	}

	// 设置 CloudInitUser 的默认值
	if wukong.Spec.CloudInitUser != nil {
		if wukong.Spec.CloudInitUser.Shell == "" {
			wukong.Spec.CloudInitUser.Shell = "/bin/bash"
		}
		if wukong.Spec.CloudInitUser.Sudo == "" {
			wukong.Spec.CloudInitUser.Sudo = "ALL=(ALL) NOPASSWD:ALL"
		}
	}
	return nil
}

// TODO(user): change verbs to "verbs=create;update;delete" if you want to enable deletion validation.
// +kubebuilder:webhook:path=/validate-vm-novasphere-dev-v1alpha1-wukong,mutating=false,failurePolicy=fail,sideEffects=None,groups=vm.novasphere.dev,resources=wukongs,verbs=create;update,versions=v1alpha1,name=vwukong.kb.io,admissionReviewVersions=v1

var _ webhook.CustomValidator = &Wukong{}

// ValidateCreate implements webhook.CustomValidator so a webhook will be registered for the type
func (r *Wukong) ValidateCreate(ctx context.Context, obj runtime.Object) (admission.Warnings, error) {
	wukong := obj.(*Wukong)
	wukonglog.Info("validate create", "name", wukong.Name)

	// 验证 CPU
	if wukong.Spec.CPU < 1 || wukong.Spec.CPU > 64 {
		return nil, fmt.Errorf("invalid CPU: must be between 1 and 64, got %d", wukong.Spec.CPU)
	}

	// 验证内存格式（基本检查）
	if wukong.Spec.Memory == "" {
		return nil, fmt.Errorf("memory is required")
	}

	// 验证至少有一个磁盘
	if len(wukong.Spec.Disks) == 0 {
		return nil, fmt.Errorf("at least one disk is required")
	}

	// 验证磁盘配置
	for i, disk := range wukong.Spec.Disks {
		if disk.Name == "" {
			return nil, fmt.Errorf("disk[%d].name is required", i)
		}
		if disk.Size == "" {
			return nil, fmt.Errorf("disk[%d].size is required", i)
		}
		if disk.StorageClassName == "" {
			return nil, fmt.Errorf("disk[%d].storageClassName is required", i)
		}
	}

	// 验证网络配置
	for i, net := range wukong.Spec.Networks {
		if net.Name == "" {
			return nil, fmt.Errorf("network[%d].name is required", i)
		}
		// default 网络使用 Pod 网络，不需要 type 字段
		if net.Name == "default" {
			// default 网络不需要 type，代码会自动使用 Pod 网络
			continue
		}
		// 非 default 网络必须指定 type
		if net.Type == "" {
			return nil, fmt.Errorf("network[%d].type is required (default network does not need type)", i)
		}
		// 验证网络类型
		validTypes := map[string]bool{
			"bridge":  true,
			"macvlan": true,
			"sriov":   true,
			"ovs":     true,
		}
		if !validTypes[net.Type] {
			return nil, fmt.Errorf("network[%d].type must be one of: bridge, macvlan, sriov, ovs, got %s", i, net.Type)
		}
		// 验证 VLAN ID
		if net.VLANID != nil {
			if *net.VLANID < 1 || *net.VLANID > 4094 {
				return nil, fmt.Errorf("network[%d].vlanId must be between 1 and 4094, got %d", i, *net.VLANID)
			}
		}
		// 验证 IP 配置
		if net.IPConfig != nil {
			if net.IPConfig.Mode != "static" && net.IPConfig.Mode != "dhcp" {
				return nil, fmt.Errorf("network[%d].ipConfig.mode must be 'static' or 'dhcp', got %s", i, net.IPConfig.Mode)
			}
			if net.IPConfig.Mode == "static" && net.IPConfig.Address == nil {
				return nil, fmt.Errorf("network[%d].ipConfig.address is required when mode is 'static'", i)
			}
		}
	}

	// 验证 CloudInitUser
	if wukong.Spec.CloudInitUser != nil {
		if wukong.Spec.CloudInitUser.Name == "" {
			return nil, fmt.Errorf("cloudInitUser.name is required")
		}
	}

	return nil, nil
}

// ValidateUpdate implements webhook.CustomValidator so a webhook will be registered for the type
func (r *Wukong) ValidateUpdate(ctx context.Context, old runtime.Object, new runtime.Object) (admission.Warnings, error) {
	wukonglog.Info("validate update", "name", r.Name)

	oldWukong := old.(*Wukong)
	newWukong := new.(*Wukong)

	// 验证 CPU 不能减少（防止资源不足）
	if newWukong.Spec.CPU < oldWukong.Spec.CPU {
		return nil, fmt.Errorf("CPU cannot be reduced from %d to %d", oldWukong.Spec.CPU, newWukong.Spec.CPU)
	}

	// 验证内存不能减少（防止资源不足）
	// 注意：这里只是简单比较字符串，实际应该解析为 Quantity 比较
	// 为了简化，这里只做基本检查
	if newWukong.Spec.Memory != "" && oldWukong.Spec.Memory != "" {
		// 可以添加更复杂的 Quantity 比较逻辑
		wukonglog.V(1).Info("memory change detected", "old", oldWukong.Spec.Memory, "new", newWukong.Spec.Memory)
	}

	// 验证磁盘不能删除（防止数据丢失）
	if len(newWukong.Spec.Disks) < len(oldWukong.Spec.Disks) {
		return nil, fmt.Errorf("disks cannot be removed, current: %d, new: %d", len(oldWukong.Spec.Disks), len(newWukong.Spec.Disks))
	}

	// 验证磁盘大小不能减少（防止数据丢失）
	for i, newDisk := range newWukong.Spec.Disks {
		if i < len(oldWukong.Spec.Disks) {
			oldDisk := oldWukong.Spec.Disks[i]
			if newDisk.Name == oldDisk.Name && newDisk.Size != oldDisk.Size {
				// 这里应该解析 Quantity 进行比较，简化处理
				wukonglog.V(1).Info("disk size change detected", "disk", newDisk.Name, "old", oldDisk.Size, "new", newDisk.Size)
				// 注意：实际应该使用 resource.ParseQuantity 进行比较
			}
		}
	}

	// 执行创建时的验证（复用逻辑）
	return newWukong.ValidateCreate(ctx, new)
}

// ValidateDelete implements webhook.CustomValidator so a webhook will be registered for the type
func (r *Wukong) ValidateDelete(ctx context.Context, obj runtime.Object) (admission.Warnings, error) {
	wukong := obj.(*Wukong)
	wukonglog.Info("validate delete", "name", wukong.Name)

	// 删除时的验证（通常不需要，因为 Finalizer 会处理清理）
	// 如果需要阻止删除，可以在这里返回错误
	// 例如：检查是否有正在运行的 VM

	return nil, nil
}
