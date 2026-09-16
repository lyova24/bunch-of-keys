use serde::Serialize;
use uuid::Uuid;

use crate::core::{CredentialField, Entry, FieldKind, Group, Node, VaultData};

#[derive(Debug, Serialize)]
pub struct VaultView {
    pub id: Uuid,
    pub nodes: Vec<NodeView>,
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
}

impl VaultView {
    pub fn from_data(id: Uuid, data: &VaultData) -> Self {
        Self {
            id,
            nodes: data.nodes.iter().map(NodeView::from).collect(),
        }
    }
}

impl From<&Node> for NodeView {
    fn from(node: &Node) -> Self {
        match node {
            Node::Group(group) => Self::Group(GroupView::from(group)),
            Node::Entry(entry) => Self::Entry(EntryView::from(entry)),
        }
    }
}

impl From<&Group> for GroupView {
    fn from(group: &Group) -> Self {
        Self {
            id: group.id,
            name: group.name.clone(),
            children: group.children.iter().map(NodeView::from).collect(),
        }
    }
}

impl From<&Entry> for EntryView {
    fn from(entry: &Entry) -> Self {
        Self {
            id: entry.id,
            name: entry.name.clone(),
            fields: entry.fields.iter().map(FieldView::from).collect(),
        }
    }
}

impl From<&CredentialField> for FieldView {
    fn from(field: &CredentialField) -> Self {
        Self {
            id: field.id,
            label: field.label.clone(),
            kind: field.kind,
            masked: field.masked,
            value: (!field.masked).then(|| field.value.clone()),
        }
    }
}
