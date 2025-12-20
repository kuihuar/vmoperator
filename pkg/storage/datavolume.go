package storage

import (
	"context"
	"fmt"
	"strings"

	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	vmv1alpha1 "github.com/kuihuar/novasphere/api/v1alpha1"
)

// ReconcileDataVolume creates or gets an existing DataVolume for the given disk configuration.
// DataVolume is used when disk.image is specified to import data from a container image.
// It returns the PVC name (created by DataVolume) and bound status.
func ReconcileDataVolume(ctx context.Context, c client.Client, disk vmv1alpha1.DiskConfig, namespace, vmName string) (string, bool, error) {
	logger := log.FromContext(ctx)
	dvName := fmt.Sprintf("%s-%s", vmName, disk.Name)
	pvcName := dvName // DataVolume 创建的 PVC 名称与 DataVolume 名称相同

	logger.Info("Reconciling DataVolume", "name", dvName, "namespace", namespace, "image", disk.Image, "size", disk.Size, "storageClass", disk.StorageClassName)

	// 使用 Unstructured 创建 DataVolume（避免直接依赖 CDI API）
	dv := &unstructured.Unstructured{}
	dv.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "cdi.kubevirt.io",
		Version: "v1beta1",
		Kind:    "DataVolume",
	})
	dv.SetName(dvName)
	dv.SetNamespace(namespace)

	// 根据 image URL 类型选择不同的 source
	// 支持 http://、https://（HTTP 源）和 docker://（registry 源）
	var source map[string]interface{}
	imageURL := disk.Image

	if strings.HasPrefix(imageURL, "http://") || strings.HasPrefix(imageURL, "https://") {
		// HTTP/HTTPS 源：直接从 URL 下载镜像文件
		logger.Info("Using HTTP source for DataVolume", "url", imageURL)
		source = map[string]interface{}{
			"http": map[string]interface{}{
				"url": imageURL,
			},
		}
	} else if strings.HasPrefix(imageURL, "docker://") {
		// Docker registry 源：从容器镜像仓库拉取
		// 去掉 docker:// 前缀，CDI 需要的是纯 URL
		registryURL := strings.TrimPrefix(imageURL, "docker://")
		logger.Info("Using registry source for DataVolume", "url", registryURL)
		source = map[string]interface{}{
			"registry": map[string]interface{}{
				// 使用容器内拉取镜像的方式（pod 模式），在 Docker Desktop 等环境下更通用
				"url":        registryURL,
				"pullMethod": "pod",
			},
		}
	} else {
		// 默认当作 registry URL（兼容旧格式）
		logger.Info("Using registry source for DataVolume (default)", "url", imageURL)
		source = map[string]interface{}{
			"registry": map[string]interface{}{
				"url":        imageURL,
				"pullMethod": "pod",
			},
		}
	}

	// 构建 DataVolume spec
	spec := map[string]interface{}{
		"source": source,
		"pvc": map[string]interface{}{
			// 注意：这里必须使用 []interface{}，否则在 DeepCopy 期间会因为 []string 触发 panic: cannot deep copy []string
			"accessModes": []interface{}{"ReadWriteOnce"},
			"resources": map[string]interface{}{
				"requests": map[string]interface{}{
					"storage": disk.Size,
				},
			},
			"storageClassName": disk.StorageClassName,
		},
	}

	if err := unstructured.SetNestedField(dv.Object, spec, "spec"); err != nil {
		logger.Error(err, "failed to set DataVolume spec")
		return "", false, err
	}

	// 检查 context 是否已取消
	if ctx.Err() != nil {
		logger.V(1).Info("Context canceled before checking DataVolume, will retry", "name", dvName, "error", ctx.Err())
		return pvcName, false, ctx.Err()
	}

	// 尝试获取现有的 DataVolume
	existingDV := &unstructured.Unstructured{}
	existingDV.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "cdi.kubevirt.io",
		Version: "v1beta1",
		Kind:    "DataVolume",
	})
	key := client.ObjectKey{Namespace: namespace, Name: dvName}
	err := c.Get(ctx, key, existingDV)
	if err != nil {
		if errors.IsNotFound(err) {
			// DataVolume 不存在，创建新的
			logger.Info("Creating DataVolume", "name", dvName, "image", disk.Image)
			if err := c.Create(ctx, dv); err != nil {
				logger.Error(err, "failed to create DataVolume", "name", dvName)
				return "", false, err
			}
			// 不等待，让 controller requeue 来检查状态
			logger.Info("DataVolume created, will check status in next reconcile", "name", dvName)
			return pvcName, false, nil
		}
		// 如果是 context canceled，返回以便 controller 处理
		if ctx.Err() != nil {
			logger.V(1).Info("Context canceled during Get DataVolume, will retry", "name", dvName)
			return pvcName, false, ctx.Err()
		}
		// 其他错误
		logger.Error(err, "failed to get DataVolume", "name", dvName)
		return "", false, err
	}

	// DataVolume 已存在，检查状态（不等待）
	logger.V(1).Info("Found existing DataVolume", "name", dvName)
	bound, err := CheckDataVolumeStatus(ctx, c, namespace, dvName)
	if err != nil {
		return pvcName, false, err
	}
	return pvcName, bound, nil
}

// CheckDataVolumeStatus checks the current status of a DataVolume (non-blocking).
// Returns true if DataVolume is ready (phase == Succeeded) and PVC is bound.
// Returns false if DataVolume is still in progress.
// Returns error if DataVolume is in Failed/Error state or other errors occur.
func CheckDataVolumeStatus(ctx context.Context, c client.Client, namespace, name string) (bool, error) {
	logger := log.FromContext(ctx)

	dv := &unstructured.Unstructured{}
	dv.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "cdi.kubevirt.io",
		Version: "v1beta1",
		Kind:    "DataVolume",
	})
	// 检查 context 是否已取消
	if ctx.Err() != nil {
		logger.V(1).Info("Context canceled, will retry in next reconcile", "name", name, "error", ctx.Err())
		return false, ctx.Err()
	}

	key := client.ObjectKey{Namespace: namespace, Name: name}
	if err := c.Get(ctx, key, dv); err != nil {
		if errors.IsNotFound(err) {
			// DataVolume 可能还在创建中
			logger.V(1).Info("DataVolume not found, may still be creating", "name", name)
			return false, nil
		}
		// 如果是 context canceled，返回特殊错误以便 controller 处理
		if ctx.Err() != nil {
			logger.V(1).Info("Context canceled during Get, will retry", "name", name)
			return false, ctx.Err()
		}
		return false, err
	}

	// 获取 phase 字段
	phase, found, err := unstructured.NestedString(dv.Object, "status", "phase")
	if err != nil {
		logger.Error(err, "failed to get DataVolume phase", "name", name)
		return false, err
	}
	if !found {
		// phase 字段不存在，可能还在初始化
		logger.V(1).Info("DataVolume phase not found, still initializing", "name", name)
		return false, nil
	}

	logger.V(1).Info("DataVolume status", "name", name, "phase", phase)

	if phase == "Succeeded" {
		logger.Info("DataVolume is ready", "name", name)
		// 检查对应的 PVC 是否已绑定（非阻塞检查）
		pvcBound, err := CheckPVCBound(ctx, c, namespace, name)
		return pvcBound, err
	}

	if phase == "Failed" || phase == "Error" {
		return false, fmt.Errorf("DataVolume %s/%s is in %s state", namespace, name, phase)
	}

	// 其他状态（Pending, ImportScheduled, ImportInProgress 等），还在进行中
	logger.V(1).Info("DataVolume is still in progress", "name", name, "phase", phase)
	return false, nil
}

// DeleteDataVolume deletes a DataVolume.
func DeleteDataVolume(ctx context.Context, c client.Client, namespace, name string) error {
	logger := log.FromContext(ctx)
	logger.Info("Deleting DataVolume", "name", name, "namespace", namespace)

	dv := &unstructured.Unstructured{}
	dv.SetGroupVersionKind(schema.GroupVersionKind{
		Group:   "cdi.kubevirt.io",
		Version: "v1beta1",
		Kind:    "DataVolume",
	})
	dv.SetName(name)
	dv.SetNamespace(namespace)

	if err := c.Delete(ctx, dv); err != nil {
		if errors.IsNotFound(err) {
			logger.V(1).Info("DataVolume already deleted", "name", name)
			return nil
		}
		logger.Error(err, "failed to delete DataVolume", "name", name)
		return err
	}

	return nil
}
