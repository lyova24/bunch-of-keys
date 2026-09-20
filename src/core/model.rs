use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;
use zeroize::Zeroize;

const MAX_NAME_CHARS: usize = 200;
const MAX_LABEL_CHARS: usize = 200;
const MAX_VALUE_BYTES: usize = 2 * 1024 * 1024;
const MAX_FIELDS_PER_ENTRY: usize = 256;

/// The encrypted payload stored inside a vault envelope.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct VaultData {
    pub schema_version: u16,
    pub nodes: Vec<Node>,
}

impl Default for VaultData {
    fn default() -> Self {
        Self {
            schema_version: 1,
            nodes: Vec::new(),
        }
    }
}

impl Drop for VaultData {
    fn drop(&mut self) {
        zeroize_nodes(&mut self.nodes);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Node {
    Group(Group),
    Entry(Entry),
}

impl Node {
    pub fn id(&self) -> Uuid {
        match self {
            Self::Group(group) => group.id,
            Self::Entry(entry) => entry.id,
        }
    }

    pub fn name(&self) -> &str {
        match self {
            Self::Group(group) => &group.name,
            Self::Entry(entry) => &entry.name,
        }
    }

    fn set_name(&mut self, name: String) {
        match self {
            Self::Group(group) => group.name = name,
            Self::Entry(entry) => entry.name = name,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Group {
    pub id: Uuid,
    pub name: String,
    pub children: Vec<Node>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Entry {
    pub id: Uuid,
    pub name: String,
    pub fields: Vec<CredentialField>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct CredentialField {
    pub id: Uuid,
    pub label: String,
    pub value: String,
    pub kind: FieldKind,
    pub masked: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FieldKind {
    #[serde(alias = "note")]
    Text,
    Secret,
    Url,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FieldInput {
    #[serde(default)]
    pub id: Option<Uuid>,
    pub label: String,
    pub value: String,
    pub kind: FieldKind,
    pub masked: bool,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ModelError {
    #[error("name must not be empty")]
    EmptyName,
    #[error("name is too long")]
    NameTooLong,
    #[error("field label must not be empty")]
    EmptyFieldLabel,
    #[error("field label is too long")]
    FieldLabelTooLong,
    #[error("field value is too large")]
    FieldValueTooLarge,
    #[error("an entry contains too many fields")]
    TooManyFields,
    #[error("the requested parent group does not exist")]
    ParentNotFound,
    #[error("the requested node does not exist")]
    NodeNotFound,
    #[error("the requested entry does not exist")]
    EntryNotFound,
    #[error("a group cannot be moved inside itself or one of its descendants")]
    CyclicMove,
    #[error("the requested node position does not exist")]
    PositionOutOfBounds,
    #[error("field identifiers must be unique inside an entry")]
    DuplicateFieldId,
}

impl VaultData {
    pub fn add_group(&mut self, parent_id: Option<Uuid>, name: &str) -> Result<Uuid, ModelError> {
        let name = validated_name(name)?;
        let id = Uuid::new_v4();
        let group = Node::Group(Group {
            id,
            name,
            children: Vec::new(),
        });
        children_mut(&mut self.nodes, parent_id)
            .ok_or(ModelError::ParentNotFound)?
            .push(group);
        Ok(id)
    }

    pub fn add_entry(
        &mut self,
        parent_id: Option<Uuid>,
        name: &str,
        fields: Vec<FieldInput>,
    ) -> Result<Uuid, ModelError> {
        let name = validated_name(name)?;
        let fields = validated_fields(fields)?;
        let id = Uuid::new_v4();
        let entry = Node::Entry(Entry { id, name, fields });
        children_mut(&mut self.nodes, parent_id)
            .ok_or(ModelError::ParentNotFound)?
            .push(entry);
        Ok(id)
    }

    pub fn replace_entry(
        &mut self,
        entry_id: Uuid,
        name: &str,
        fields: Vec<FieldInput>,
    ) -> Result<(), ModelError> {
        let name = validated_name(name)?;
        let fields = validated_fields(fields)?;
        let entry = find_entry_mut(&mut self.nodes, entry_id).ok_or(ModelError::EntryNotFound)?;
        entry.name = name;
        entry.fields = fields;
        Ok(())
    }

    pub fn rename_node(&mut self, node_id: Uuid, name: &str) -> Result<(), ModelError> {
        let name = validated_name(name)?;
        let node = find_node_mut(&mut self.nodes, node_id).ok_or(ModelError::NodeNotFound)?;
        node.set_name(name);
        Ok(())
    }

    pub fn delete_node(&mut self, node_id: Uuid) -> Result<(), ModelError> {
        if remove_node(&mut self.nodes, node_id) {
            Ok(())
        } else {
            Err(ModelError::NodeNotFound)
        }
    }

    pub fn move_node(
        &mut self,
        node_id: Uuid,
        parent_id: Option<Uuid>,
        index: usize,
    ) -> Result<(), ModelError> {
        let (current_parent_id, current_index) =
            node_location(&self.nodes, node_id, None).ok_or(ModelError::NodeNotFound)?;

        if parent_id == Some(node_id) {
            return Err(ModelError::CyclicMove);
        }

        if let Some(parent_id) = parent_id {
            let node = find_node(&self.nodes, node_id).ok_or(ModelError::NodeNotFound)?;
            if matches!(node, Node::Group(group) if contains_node(&group.children, parent_id)) {
                return Err(ModelError::CyclicMove);
            }
            if children(&self.nodes, Some(parent_id)).is_none() {
                return Err(ModelError::ParentNotFound);
            }
        }

        let mut target_len = children(&self.nodes, parent_id)
            .ok_or(ModelError::ParentNotFound)?
            .len();
        if current_parent_id == parent_id {
            target_len -= 1;
        }
        if index > target_len {
            return Err(ModelError::PositionOutOfBounds);
        }

        if current_parent_id == parent_id && current_index == index {
            return Ok(());
        }

        let node = take_node(&mut self.nodes, node_id).ok_or(ModelError::NodeNotFound)?;
        children_mut(&mut self.nodes, parent_id)
            .ok_or(ModelError::ParentNotFound)?
            .insert(index, node);
        Ok(())
    }

    pub fn field(&self, entry_id: Uuid, field_id: Uuid) -> Option<&CredentialField> {
        find_entry(&self.nodes, entry_id)?
            .fields
            .iter()
            .find(|field| field.id == field_id)
    }

    pub fn extend_root(&mut self, nodes: Vec<Node>) {
        self.nodes.extend(nodes);
    }

    pub fn validate(&self) -> Result<(), ModelError> {
        validate_nodes(&self.nodes)
    }
}

fn validated_name(name: &str) -> Result<String, ModelError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(ModelError::EmptyName);
    }
    if name.chars().count() > MAX_NAME_CHARS {
        return Err(ModelError::NameTooLong);
    }
    Ok(name.to_owned())
}

fn validated_fields(fields: Vec<FieldInput>) -> Result<Vec<CredentialField>, ModelError> {
    if fields.len() > MAX_FIELDS_PER_ENTRY {
        return Err(ModelError::TooManyFields);
    }

    let mut result = Vec::with_capacity(fields.len());
    for input in fields {
        let label = input.label.trim();
        if label.is_empty() {
            return Err(ModelError::EmptyFieldLabel);
        }
        if label.chars().count() > MAX_LABEL_CHARS {
            return Err(ModelError::FieldLabelTooLong);
        }
        if input.value.len() > MAX_VALUE_BYTES {
            return Err(ModelError::FieldValueTooLarge);
        }
        let id = input.id.unwrap_or_else(Uuid::new_v4);
        if result.iter().any(|field: &CredentialField| field.id == id) {
            return Err(ModelError::DuplicateFieldId);
        }
        result.push(CredentialField {
            id,
            label: label.to_owned(),
            value: input.value,
            kind: input.kind,
            masked: input.masked,
        });
    }
    Ok(result)
}

fn children_mut(nodes: &mut Vec<Node>, parent_id: Option<Uuid>) -> Option<&mut Vec<Node>> {
    let Some(parent_id) = parent_id else {
        return Some(nodes);
    };

    for node in nodes {
        if let Node::Group(group) = node {
            if group.id == parent_id {
                return Some(&mut group.children);
            }
            if let Some(children) = children_mut(&mut group.children, Some(parent_id)) {
                return Some(children);
            }
        }
    }
    None
}

fn children(nodes: &[Node], parent_id: Option<Uuid>) -> Option<&[Node]> {
    let Some(parent_id) = parent_id else {
        return Some(nodes);
    };

    for node in nodes {
        if let Node::Group(group) = node {
            if group.id == parent_id {
                return Some(&group.children);
            }
            if let Some(children) = children(&group.children, Some(parent_id)) {
                return Some(children);
            }
        }
    }
    None
}

fn find_node(nodes: &[Node], node_id: Uuid) -> Option<&Node> {
    for node in nodes {
        if node.id() == node_id {
            return Some(node);
        }
        if let Node::Group(group) = node
            && let Some(found) = find_node(&group.children, node_id)
        {
            return Some(found);
        }
    }
    None
}

fn contains_node(nodes: &[Node], node_id: Uuid) -> bool {
    find_node(nodes, node_id).is_some()
}

fn node_location(
    nodes: &[Node],
    node_id: Uuid,
    parent_id: Option<Uuid>,
) -> Option<(Option<Uuid>, usize)> {
    for (index, node) in nodes.iter().enumerate() {
        if node.id() == node_id {
            return Some((parent_id, index));
        }
        if let Node::Group(group) = node
            && let Some(location) = node_location(&group.children, node_id, Some(group.id))
        {
            return Some(location);
        }
    }
    None
}

fn take_node(nodes: &mut Vec<Node>, node_id: Uuid) -> Option<Node> {
    if let Some(index) = nodes.iter().position(|node| node.id() == node_id) {
        return Some(nodes.remove(index));
    }
    for node in nodes {
        if let Node::Group(group) = node
            && let Some(found) = take_node(&mut group.children, node_id)
        {
            return Some(found);
        }
    }
    None
}

fn find_node_mut(nodes: &mut [Node], node_id: Uuid) -> Option<&mut Node> {
    for node in nodes {
        if node.id() == node_id {
            return Some(node);
        }
        if let Node::Group(group) = node
            && let Some(found) = find_node_mut(&mut group.children, node_id)
        {
            return Some(found);
        }
    }
    None
}

fn find_entry_mut(nodes: &mut [Node], entry_id: Uuid) -> Option<&mut Entry> {
    for node in nodes {
        match node {
            Node::Entry(entry) if entry.id == entry_id => return Some(entry),
            Node::Group(group) => {
                if let Some(found) = find_entry_mut(&mut group.children, entry_id) {
                    return Some(found);
                }
            }
            Node::Entry(_) => {}
        }
    }
    None
}

fn find_entry(nodes: &[Node], entry_id: Uuid) -> Option<&Entry> {
    for node in nodes {
        match node {
            Node::Entry(entry) if entry.id == entry_id => return Some(entry),
            Node::Group(group) => {
                if let Some(found) = find_entry(&group.children, entry_id) {
                    return Some(found);
                }
            }
            Node::Entry(_) => {}
        }
    }
    None
}

fn remove_node(nodes: &mut Vec<Node>, node_id: Uuid) -> bool {
    if let Some(index) = nodes.iter().position(|node| node.id() == node_id) {
        nodes.remove(index);
        return true;
    }
    for node in nodes {
        if let Node::Group(group) = node
            && remove_node(&mut group.children, node_id)
        {
            return true;
        }
    }
    false
}

fn validate_nodes(nodes: &[Node]) -> Result<(), ModelError> {
    for node in nodes {
        validated_name(node.name())?;
        match node {
            Node::Group(group) => validate_nodes(&group.children)?,
            Node::Entry(entry) => {
                let fields = entry
                    .fields
                    .iter()
                    .cloned()
                    .map(|field| FieldInput {
                        id: Some(field.id),
                        label: field.label,
                        value: field.value,
                        kind: field.kind,
                        masked: field.masked,
                    })
                    .collect();
                validated_fields(fields)?;
            }
        }
    }
    Ok(())
}

fn zeroize_nodes(nodes: &mut [Node]) {
    for node in nodes {
        match node {
            Node::Group(group) => {
                group.name.zeroize();
                zeroize_nodes(&mut group.children);
            }
            Node::Entry(entry) => {
                entry.name.zeroize();
                for field in &mut entry.fields {
                    field.label.zeroize();
                    field.value.zeroize();
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn legacy_note_fields_load_as_text_without_data_loss() {
        let field: CredentialField = serde_json::from_str(
            r#"{
                "id": "f8dd3fbe-e083-49f9-8e4f-6ab405dbfeea",
                "label": "Recovery notes",
                "value": "first line\nsecond line",
                "kind": "note",
                "masked": false
            }"#,
        )
        .unwrap();

        assert_eq!(field.label, "Recovery notes");
        assert_eq!(field.value, "first line\nsecond line");
        assert_eq!(field.kind, FieldKind::Text);
        assert_eq!(
            serde_json::to_value(field).unwrap()["kind"],
            serde_json::json!("text")
        );
    }

    fn field(label: &str, value: &str, masked: bool) -> FieldInput {
        FieldInput {
            id: None,
            label: label.to_owned(),
            value: value.to_owned(),
            kind: if masked {
                FieldKind::Secret
            } else {
                FieldKind::Text
            },
            masked,
        }
    }

    #[test]
    fn supports_nested_groups_and_field_lookup() {
        let mut vault = VaultData::default();
        let work = vault.add_group(None, "Work").unwrap();
        let infra = vault.add_group(Some(work), "Infrastructure").unwrap();
        let entry = vault
            .add_entry(
                Some(infra),
                "Deployment",
                vec![field("Token", "example-secret", true)],
            )
            .unwrap();
        let field_id = match &vault.nodes[0] {
            Node::Group(group) => match &group.children[0] {
                Node::Group(group) => match &group.children[0] {
                    Node::Entry(entry) => entry.fields[0].id,
                    Node::Group(_) => panic!("expected entry"),
                },
                Node::Entry(_) => panic!("expected group"),
            },
            Node::Entry(_) => panic!("expected group"),
        };

        assert_eq!(
            vault
                .field(entry, field_id)
                .map(|field| field.value.as_str()),
            Some("example-secret")
        );
        vault.validate().unwrap();
    }

    #[test]
    fn deleting_a_group_deletes_its_subtree() {
        let mut vault = VaultData::default();
        let group = vault.add_group(None, "Disposable").unwrap();
        let entry = vault
            .add_entry(Some(group), "Entry", vec![field("Value", "x", false)])
            .unwrap();

        vault.delete_node(group).unwrap();

        assert!(vault.nodes.is_empty());
        assert!(matches!(
            vault.replace_entry(entry, "Entry", Vec::new()),
            Err(ModelError::EntryNotFound)
        ));
    }

    #[test]
    fn replacing_an_entry_preserves_the_requested_field_order_and_properties() {
        let mut vault = VaultData::default();
        let entry_id = vault
            .add_entry(
                None,
                "Ordered",
                vec![
                    field("Username", "alice", false),
                    field("Password", "secret", true),
                ],
            )
            .unwrap();
        let original = find_entry(&vault.nodes, entry_id).unwrap().fields.clone();
        let reordered = original
            .iter()
            .rev()
            .map(|field| FieldInput {
                id: Some(field.id),
                label: field.label.clone(),
                value: field.value.clone(),
                kind: field.kind,
                masked: field.masked,
            })
            .collect();

        vault.replace_entry(entry_id, "Ordered", reordered).unwrap();

        let fields = &find_entry(&vault.nodes, entry_id).unwrap().fields;
        assert_eq!(fields[0], original[1]);
        assert_eq!(fields[1], original[0]);
    }

    #[test]
    fn moves_nodes_between_groups_and_preserves_requested_order() {
        let mut vault = VaultData::default();
        let work = vault.add_group(None, "Work").unwrap();
        let personal = vault.add_group(None, "Personal").unwrap();
        let entry = vault
            .add_entry(Some(work), "Deployment", vec![field("Token", "x", true)])
            .unwrap();
        let archive = vault.add_group(Some(personal), "Archive").unwrap();

        vault.move_node(entry, Some(personal), 0).unwrap();
        vault.move_node(archive, Some(work), 0).unwrap();
        vault.move_node(personal, None, 0).unwrap();

        let Node::Group(personal_group) = &vault.nodes[0] else {
            panic!("expected Personal first");
        };
        assert_eq!(personal_group.id, personal);
        assert_eq!(personal_group.children[0].id(), entry);
        let Node::Group(work_group) = &vault.nodes[1] else {
            panic!("expected Work second");
        };
        assert_eq!(work_group.children[0].id(), archive);
    }

    #[test]
    fn rejects_cyclic_and_out_of_bounds_moves_without_mutating_the_vault() {
        let mut vault = VaultData::default();
        let parent = vault.add_group(None, "Parent").unwrap();
        let child = vault.add_group(Some(parent), "Child").unwrap();
        let original = vault.clone();

        assert_eq!(
            vault.move_node(parent, Some(child), 0),
            Err(ModelError::CyclicMove)
        );
        assert_eq!(vault, original);
        assert_eq!(
            vault.move_node(child, None, 8),
            Err(ModelError::PositionOutOfBounds)
        );
        assert_eq!(vault, original);
    }
}
