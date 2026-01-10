package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// WukongSnapshotSpec defines the desired state of WukongSnapshot
type WukongSnapshotSpec struct {
	// WukongName is the name of the Wukong instance to snapshot
	// +kubebuilder:validation:Required
	// +required
	WukongName string `json:"wukongName"`
}

// WukongSnapshotStatus defines the observed state of WukongSnapshot
type WukongSnapshotStatus struct {
	// Phase represents the current phase of the snapshot
	// Valid values: Pending, Creating, Succeeded, Failed
	// +optional
	Phase string `json:"phase,omitempty"`

	// SnapshotName is the name of the underlying KubeVirt VirtualMachineSnapshot
	// +optional
	SnapshotName string `json:"snapshotName,omitempty"`

	// CreationTime is the time when the snapshot was created
	// +optional
	CreationTime *metav1.Time `json:"creationTime,omitempty"`

	// Error message if the snapshot failed
	// +optional
	Error string `json:"error,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// WukongSnapshot is the Schema for the wukongsnapshots API
type WukongSnapshot struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   WukongSnapshotSpec   `json:"spec,omitempty"`
	Status WukongSnapshotStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// WukongSnapshotList contains a list of WukongSnapshot
type WukongSnapshotList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []WukongSnapshot `json:"items"`
}

func init() {
	SchemeBuilder.Register(&WukongSnapshot{}, &WukongSnapshotList{})
}
