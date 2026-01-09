package network

// NMState 类型定义
// 为了避免使用 unstructured，我们定义本地类型
// 这些类型对应 NodeNetworkConfigurationPolicy 的 spec.desiredState 结构

// DesiredState 表示 NMState 的期望状态
type DesiredState struct {
	Interfaces []Interface `json:"interfaces"`
}

// Interface 表示网络接口配置
type Interface struct {
	Name   string        `json:"name"`
	Type   string        `json:"type"`
	State  string        `json:"state,omitempty"`
	IPv4   *IPv4Config   `json:"ipv4,omitempty"`
	VLAN   *VLANConfig   `json:"vlan,omitempty"`
	Bridge *BridgeConfig `json:"bridge,omitempty"`
}

// IPv4Config 表示 IPv4 配置
type IPv4Config struct {
	Enabled bool          `json:"enabled"`
	Address []IPv4Address `json:"address,omitempty"`
}

// IPv4Address 表示 IPv4 地址
type IPv4Address struct {
	IP           string `json:"ip"`
	PrefixLength int64  `json:"prefix-length"` // 使用 int64 避免 deep copy 问题
}

// VLANConfig 表示 VLAN 配置
type VLANConfig struct {
	BaseIface string `json:"base-iface"`
	ID        int64  `json:"id"` // 使用 int64 避免 deep copy 问题
}

// BridgeConfig 表示桥接配置
type BridgeConfig struct {
	Options BridgeOptions `json:"options,omitempty"`
	Port    []BridgePort  `json:"port,omitempty"`
}

// BridgeOptions 表示桥接选项
type BridgeOptions struct {
	STP STPConfig `json:"stp,omitempty"`
}

// STPConfig 表示 STP 配置
type STPConfig struct {
	Enabled bool `json:"enabled"`
}

// BridgePort 表示桥接端口
type BridgePort struct {
	Name string `json:"name"`
}

// NodeNetworkConfigurationPolicySpec 表示 NodeNetworkConfigurationPolicy 的 spec
type NodeNetworkConfigurationPolicySpec struct {
	DesiredState DesiredState `json:"desiredState"`
}

// NodeNetworkConfigurationPolicy 表示完整的 NodeNetworkConfigurationPolicy 资源
type NodeNetworkConfigurationPolicy struct {
	APIVersion string                             `json:"apiVersion"`
	Kind       string                             `json:"kind"`
	Metadata   map[string]interface{}             `json:"metadata"`
	Spec       NodeNetworkConfigurationPolicySpec `json:"spec"`
}
