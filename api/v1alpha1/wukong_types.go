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
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Phase constants for Wukong
const (
	PhasePending  = "Pending"
	PhaseCreating = "Creating"
	PhaseRunning  = "Running"
	PhaseStopped  = "Stopped"
	PhaseError    = "Error"
)

// WukongSpec defines the desired state of Wukong
type WukongSpec struct {
	// CPU is the number of CPU cores for the virtual machine
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=64
	// +required
	CPU int `json:"cpu"`

	// Memory is the memory size for the virtual machine (e.g., "8Gi", "4G")
	// +kubebuilder:validation:Pattern=`^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|K|M|G|T|P|E)?$`
	// +required
	Memory string `json:"memory"`

	// OSImage is the operating system image for Cloud-Init configuration
	// +optional
	OSImage string `json:"osImage,omitempty"`

	// SSHKeySecret is the name of the Secret containing SSH public keys
	// +optional
	SSHKeySecret string `json:"sshKeySecret,omitempty"`

	// CloudInitUser defines the default user to be created by Cloud-Init
	// +optional
	CloudInitUser *CloudInitUserSpec `json:"cloudInitUser,omitempty"`

	// Networks defines the network interfaces for the virtual machine
	// +optional
	Networks []NetworkConfig `json:"networks,omitempty"`

	// Disks defines the storage disks for the virtual machine
	// +optional
	Disks []DiskConfig `json:"disks,omitempty"`

	// HighAvailability defines high availability configuration
	// +optional
	HighAvailability *HighAvailabilitySpec `json:"highAvailability,omitempty"`

	// StartStrategy defines the start strategy for the virtual machine
	// +optional
	StartStrategy *StartStrategySpec `json:"startStrategy,omitempty"`
}

// NetworkConfig defines a network interface configuration
type NetworkConfig struct {
	// Name is the unique name of the network interface
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	// +required
	Name string `json:"name"`

	// Type is the network type: bridge, macvlan, sriov, or ovs
	// +kubebuilder:validation:Enum=bridge;macvlan;sriov;ovs
	// +required
	Type string `json:"type"`

	// NADName is the name of an existing NetworkAttachmentDefinition
	// If empty, the operator will create a new NAD
	// +optional
	NADName string `json:"nadName,omitempty"`

	// VLANID is the VLAN ID (1-4094)
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=4094
	// +optional
	VLANID *int `json:"vlanId,omitempty"`

	// BridgeName is the bridge name (for bridge and ovs types)
	// +optional
	BridgeName string `json:"bridgeName,omitempty"`

	// IPConfig defines the IP configuration for this network
	// +optional
	IPConfig *IPConfigSpec `json:"ipConfig,omitempty"`
}

// IPConfigSpec defines IP configuration for a network interface
type IPConfigSpec struct {
	// Mode is the IP acquisition mode: static or dhcp
	// +kubebuilder:validation:Enum=static;dhcp
	// +required
	Mode string `json:"mode"`

	// Address is the IP address and subnet mask (required for static mode)
	// Format: "192.168.1.10/24"
	// +optional
	Address *string `json:"address,omitempty"`

	// Gateway is the gateway address (for static mode)
	// +optional
	Gateway *string `json:"gateway,omitempty"`

	// DNSServers is a list of DNS server addresses
	// +optional
	DNSServers []string `json:"dnsServers,omitempty"`
}

// DiskConfig defines a storage disk configuration
type DiskConfig struct {
	// Name is the unique name of the disk
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	// +required
	Name string `json:"name"`

	// Size is the disk size (e.g., "80Gi", "500G")
	// +kubebuilder:validation:Pattern=`^[0-9]+(\.[0-9]+)?(Ki|Mi|Gi|Ti|Pi|Ei|K|M|G|T|P|E)?$`
	// +required
	Size string `json:"size"`

	// StorageClassName is the name of the StorageClass to use
	// +required
	StorageClassName string `json:"storageClassName"`

	// Boot indicates whether this is the boot disk
	// +optional
	Boot bool `json:"boot,omitempty"`

	// Image is the container image URL to create the disk from (uses DataVolume)
	// If specified, a DataVolume will be created to import the image
	// +optional
	Image string `json:"image,omitempty"`
}

// HighAvailabilitySpec defines high availability configuration
type HighAvailabilitySpec struct {
	// RestartPolicy is the restart policy: Always, OnFailure, or Never
	// +kubebuilder:validation:Enum=Always;OnFailure;Never
	// +optional
	RestartPolicy string `json:"restartPolicy,omitempty"`

	// AntiAffinity enables pod anti-affinity to prevent multiple VMs on the same node
	// +optional
	AntiAffinity bool `json:"antiAffinity,omitempty"`

	// NodeSelector is a node selector for scheduling
	// +optional
	NodeSelector map[string]string `json:"nodeSelector,omitempty"`

	// Tolerations are tolerations for node taints
	// +optional
	Tolerations []corev1.Toleration `json:"tolerations,omitempty"`
}

// StartStrategySpec defines the start strategy for the virtual machine
type StartStrategySpec struct {
	// RunStrategy is the run strategy: Always, RerunOnFailure, or Manual
	// +kubebuilder:validation:Enum=Always;RerunOnFailure;Manual
	// +optional
	RunStrategy string `json:"runStrategy,omitempty"`

	// AutoStart indicates whether to automatically start the VM
	// +optional
	AutoStart bool `json:"autoStart,omitempty"`
}

// CloudInitUserSpec defines the user to be created by Cloud-Init
type CloudInitUserSpec struct {
	// Name is the username to be created
	// +kubebuilder:validation:Required
	// +required
	Name string `json:"name"`

	// Password is the password for the user (plain text, will be hashed by Cloud-Init)
	// Note: For security, consider using PasswordHash instead
	// +optional
	Password string `json:"password,omitempty"`

	// PasswordHash is the hashed password (if provided, Password will be ignored)
	// Password hash can be generated using: openssl passwd -1 <password>
	// or: python3 -c "import crypt; print(crypt.crypt('password', crypt.mksalt(crypt.METHOD_SHA512)))"
	// +optional
	PasswordHash string `json:"passwordHash,omitempty"`

	// Sudo specifies sudo access for the user
	// Default: "ALL=(ALL) NOPASSWD:ALL"
	// +optional
	Sudo string `json:"sudo,omitempty"`

	// Shell is the default shell for the user
	// Default: "/bin/bash"
	// +optional
	Shell string `json:"shell,omitempty"`

	// Groups are additional groups the user should belong to
	// +optional
	Groups []string `json:"groups,omitempty"`

	// LockPasswd indicates whether to lock the password
	// Default: false
	// +optional
	LockPasswd bool `json:"lockPasswd,omitempty"`
}

// WukongStatus defines the observed state of Wukong
type WukongStatus struct {
	// Phase represents the current phase of the virtual machine
	// Valid values: Pending, Creating, Running, Stopped, Error
	// +kubebuilder:validation:Enum=Pending;Creating;Running;Stopped;Error
	// +optional
	Phase string `json:"phase,omitempty"`

	// VMName is the name of the corresponding KubeVirt VirtualMachine
	// +optional
	VMName string `json:"vmName,omitempty"`

	// NodeName is the name of the node where the VM is running
	// +optional
	NodeName string `json:"nodeName,omitempty"`

	// Conditions represent the current state of the Wukong resource
	// Each condition has a unique type and reflects the status of a specific aspect of the resource
	//
	// Standard condition types include:
	// - "Ready": the VM is ready and running
	// - "NetworksConfigured": all networks are configured
	// - "VolumesBound": all volumes are bound
	//
	// The status of each condition is one of True, False, or Unknown
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// Networks represents the status of network interfaces
	// +optional
	Networks []NetworkStatus `json:"networks,omitempty"`

	// Volumes represents the status of storage volumes
	// +optional
	Volumes []VolumeStatus `json:"volumes,omitempty"`
}

// NetworkStatus represents the status of a network interface
type NetworkStatus struct {
	// Name is the name of the network interface
	// +required
	Name string `json:"name"`

	// Interface is the network interface name in the VM (e.g., "eth0", "net1")
	// +optional
	Interface string `json:"interface,omitempty"`

	// IPAddress is the IP address assigned to this interface
	// +optional
	IPAddress string `json:"ipAddress,omitempty"`

	// MACAddress is the MAC address of this interface
	// +optional
	MACAddress string `json:"macAddress,omitempty"`

	// NADName is the name of the NetworkAttachmentDefinition used
	// +optional
	NADName string `json:"nadName,omitempty"`
}

// VolumeStatus represents the status of a storage volume
type VolumeStatus struct {
	// Name is the name of the volume
	// +required
	Name string `json:"name"`

	// PVCName is the name of the PersistentVolumeClaim
	// +optional
	PVCName string `json:"pvcName,omitempty"`

	// Bound indicates whether the PVC is bound
	// +optional
	Bound bool `json:"bound,omitempty"`

	// Size is the actual size of the volume
	// +optional
	Size string `json:"size,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// Wukong is the Schema for the wukongs API
type Wukong struct {
	metav1.TypeMeta `json:",inline"`

	// metadata is a standard object metadata
	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// spec defines the desired state of Wukong
	// +required
	Spec WukongSpec `json:"spec"`

	// status defines the observed state of Wukong
	// +optional
	Status WukongStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// WukongList contains a list of Wukong
type WukongList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []Wukong `json:"items"`
}

func init() {
	SchemeBuilder.Register(&Wukong{}, &WukongList{})
}
