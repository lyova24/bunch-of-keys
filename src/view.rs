use serde::Serialize;
use uuid::Uuid;

use crate::core::{CredentialField, Entry, FieldKind, Group, Node, SshKey, VaultData};

#[derive(Debug, Serialize)]
pub struct VaultView {
    pub id: Uuid,
    pub ssh_keys: Vec<SshKeyView>,
    pub nodes: Vec<NodeView>,
}

#[derive(Debug, Clone, Serialize)]
pub struct SshKeyView {
    pub id: Uuid,
    pub name: String,
    pub algorithm: String,
    pub fingerprint: String,
    pub encrypted: bool,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum NodeView {
    Group(GroupView),
    Entry(EntryView),
}

#[derive(Debug, Serialize)]
pub struct GroupView {
    pub id: Uuid,
    pub name: String,
    pub children: Vec<NodeView>,
}

#[derive(Debug, Serialize)]
pub struct EntryView {
    pub id: Uuid,
    pub name: String,
    pub fields: Vec<FieldView>,
}

#[derive(Debug, Serialize)]
pub struct FieldView {
    pub id: Uuid,
    pub label: String,
    pub kind: FieldKind,
    pub masked: bool,
    pub value: Option<String>,
    pub ssh: Option<SshConnectionView>,
}

#[derive(Debug, Serialize)]
pub struct SshConnectionView {
    pub user: String,
    pub address: String,
    pub port: Option<u16>,
    pub key: SshKeyView,
}

impl VaultView {
    pub fn from_data(id: Uuid, data: &VaultData) -> Self {
        Self {
            id,
            ssh_keys: data.ssh_keys.iter().map(SshKeyView::from).collect(),
            nodes: data
                .nodes
                .iter()
                .map(|node| NodeView::from_data(node, data))
                .collect(),
        }
    }
}

impl NodeView {
    fn from_data(node: &Node, data: &VaultData) -> Self {
        match node {
            Node::Group(group) => Self::Group(GroupView::from_data(group, data)),
            Node::Entry(entry) => Self::Entry(EntryView::from_data(entry, data)),
        }
    }
}

impl GroupView {
    fn from_data(group: &Group, data: &VaultData) -> Self {
        Self {
            id: group.id,
            name: group.name.clone(),
            children: group
                .children
                .iter()
                .map(|node| NodeView::from_data(node, data))
                .collect(),
        }
    }
}

impl EntryView {
    fn from_data(entry: &Entry, data: &VaultData) -> Self {
        Self {
            id: entry.id,
            name: entry.name.clone(),
            fields: entry
                .fields
                .iter()
                .map(|field| FieldView::from_data(field, data))
                .collect(),
        }
    }
}

impl FieldView {
    fn from_data(field: &CredentialField, data: &VaultData) -> Self {
        Self {
            id: field.id,
            label: field.label.clone(),
            kind: field.kind,
            masked: field.masked,
            value: (!field.masked && field.kind != FieldKind::Ssh).then(|| field.value.clone()),
            ssh: field.ssh.as_ref().and_then(|ssh| {
                data.ssh_key(ssh.key_id).map(|key| SshConnectionView {
                    user: ssh.user.clone(),
                    address: ssh.address.clone(),
                    port: ssh.port,
                    key: SshKeyView::from(key),
                })
            }),
        }
    }
}

impl From<&SshKey> for SshKeyView {
    fn from(key: &SshKey) -> Self {
        Self {
            id: key.id,
            name: key.name.clone(),
            algorithm: key.algorithm.clone(),
            fingerprint: key.fingerprint.clone(),
            encrypted: key.encrypted,
        }
    }
}
