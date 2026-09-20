use serde::{Deserialize, Serialize};
use ssh_key::{HashAlg, PrivateKey};
use thiserror::Error;
use uuid::Uuid;
use zeroize::Zeroize;

const MAX_NAME_CHARS: usize = 200;
const MAX_LABEL_CHARS: usize = 200;
const MAX_VALUE_BYTES: usize = 2 * 1024 * 1024;
const MAX_FIELDS_PER_ENTRY: usize = 256;
const CURRENT_SCHEMA_VERSION: u16 = 2;

/// The encrypted payload stored inside a vault envelope.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct VaultData {
    pub schema_version: u16,
    #[serde(default)]
    pub ssh_keys: Vec<SshKey>,
    pub nodes: Vec<Node>,
}

impl Default for VaultData {
    fn default() -> Self {
        Self {
            schema_version: CURRENT_SCHEMA_VERSION,
            ssh_keys: Vec::new(),
            nodes: Vec::new(),
        }
    }
}

impl Drop for VaultData {
    fn drop(&mut self) {
        for key in &mut self.ssh_keys {
            key.name.zeroize();
            key.private_key.zeroize();
            key.algorithm.zeroize();
            key.fingerprint.zeroize();
        }
        zeroize_nodes(&mut self.nodes);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SshKey {
    pub id: Uuid,
    pub name: String,
    pub private_key: String,
    pub algorithm: String,
    pub fingerprint: String,
    pub encrypted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SshConnection {
    pub user: String,
    pub address: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub port: Option<u16>,
    pub key_id: Uuid,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ssh: Option<SshConnection>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum FieldKind {
    #[serde(alias = "note")]
    Text,
    Secret,
    Url,
    Ssh,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FieldInput {
    #[serde(default)]
    pub id: Option<Uuid>,
    pub label: String,
    pub value: String,
    pub kind: FieldKind,
    pub masked: bool,
    #[serde(default)]
    pub ssh: Option<SshConnection>,
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
    #[error("vault schema version is not supported")]
    UnsupportedSchema,
    #[error("SSH key name must not be empty")]
    EmptySshKeyName,
    #[error("SSH key name is too long")]
    SshKeyNameTooLong,
    #[error("an SSH key with this name already exists")]
    DuplicateSshKeyName,
    #[error("SSH private key is malformed or unsupported")]
    InvalidSshPrivateKey,
    #[error("the requested SSH key does not exist")]
    SshKeyNotFound,
    #[error("SSH user must not be empty and cannot contain whitespace or @")]
    InvalidSshUser,
    #[error(
        "SSH address must be a hostname or IP address without whitespace, @, /, or a leading dash"
    )]
    InvalidSshAddress,
    #[error("SSH field must reference a named SSH key")]
    MissingSshKey,
    #[error("non-SSH fields cannot contain SSH connection data")]
    UnexpectedSshData,
    #[error("SSH key is still used by: {0}")]
    SshKeyInUse(String),
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
        let fields = validated_fields(fields, &self.ssh_keys)?;
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
        let fields = validated_fields(fields, &self.ssh_keys)?;
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

    pub fn ssh_key(&self, key_id: Uuid) -> Option<&SshKey> {
        self.ssh_keys.iter().find(|key| key.id == key_id)
    }

    pub fn add_ssh_key(&mut self, name: &str, private_key: &str) -> Result<Uuid, ModelError> {
        let name = validated_ssh_key_name(name)?;
        self.ensure_unique_ssh_key_name(&name, None)?;
        let (private_key, algorithm, fingerprint, encrypted) = parse_ssh_key(private_key)?;
        let id = Uuid::new_v4();
        self.ssh_keys.push(SshKey {
            id,
            name,
            private_key,
            algorithm,
            fingerprint,
            encrypted,
        });
        Ok(id)
    }

    pub fn update_ssh_key(
        &mut self,
        key_id: Uuid,
        name: &str,
        private_key: Option<&str>,
    ) -> Result<(), ModelError> {
        let name = validated_ssh_key_name(name)?;
        self.ensure_unique_ssh_key_name(&name, Some(key_id))?;
        let replacement = private_key.map(parse_ssh_key).transpose()?;
        let key = self
            .ssh_keys
            .iter_mut()
            .find(|key| key.id == key_id)
            .ok_or(ModelError::SshKeyNotFound)?;
        key.name = name;
        if let Some((private_key, algorithm, fingerprint, encrypted)) = replacement {
            key.private_key.zeroize();
            key.private_key = private_key;
            key.algorithm = algorithm;
            key.fingerprint = fingerprint;
            key.encrypted = encrypted;
        }
        Ok(())
    }

    pub fn delete_ssh_key(&mut self, key_id: Uuid) -> Result<(), ModelError> {
        if !self.ssh_keys.iter().any(|key| key.id == key_id) {
            return Err(ModelError::SshKeyNotFound);
        }
        let references = ssh_key_references(&self.nodes, key_id);
        if !references.is_empty() {
            return Err(ModelError::SshKeyInUse(references.join(", ")));
        }
        let index = self
            .ssh_keys
            .iter()
            .position(|key| key.id == key_id)
            .ok_or(ModelError::SshKeyNotFound)?;
        self.ssh_keys.remove(index);
        Ok(())
    }

    pub fn extend_root(&mut self, nodes: Vec<Node>) {
        self.nodes.extend(nodes);
    }

    pub fn validate(&self) -> Result<(), ModelError> {
        if !(1..=CURRENT_SCHEMA_VERSION).contains(&self.schema_version) {
            return Err(ModelError::UnsupportedSchema);
        }
        let mut names = Vec::with_capacity(self.ssh_keys.len());
        for key in &self.ssh_keys {
            let name = validated_ssh_key_name(&key.name)?;
            if names
                .iter()
                .any(|existing: &String| existing.eq_ignore_ascii_case(&name))
            {
                return Err(ModelError::DuplicateSshKeyName);
            }
            names.push(name);
            let (_, algorithm, fingerprint, encrypted) = parse_ssh_key(&key.private_key)?;
            if key.algorithm != algorithm
                || key.fingerprint != fingerprint
                || key.encrypted != encrypted
            {
                return Err(ModelError::InvalidSshPrivateKey);
            }
        }
        validate_nodes(&self.nodes, &self.ssh_keys)
    }

    pub fn migrate(&mut self) -> Result<(), ModelError> {
        self.validate()?;
        self.schema_version = CURRENT_SCHEMA_VERSION;
        Ok(())
    }

    fn ensure_unique_ssh_key_name(
        &self,
        name: &str,
        except: Option<Uuid>,
    ) -> Result<(), ModelError> {
        if self
            .ssh_keys
            .iter()
            .any(|key| Some(key.id) != except && key.name.eq_ignore_ascii_case(name))
        {
            return Err(ModelError::DuplicateSshKeyName);
        }
        Ok(())
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

fn validated_fields(
    fields: Vec<FieldInput>,
    ssh_keys: &[SshKey],
) -> Result<Vec<CredentialField>, ModelError> {
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
        let ssh = match input.kind {
            FieldKind::Ssh => {
                let mut ssh = input.ssh.ok_or(ModelError::MissingSshKey)?;
                ssh.user = validated_ssh_user(&ssh.user)?;
                ssh.address = validated_ssh_address(&ssh.address)?;
                if !ssh_keys.iter().any(|key| key.id == ssh.key_id) {
                    return Err(ModelError::SshKeyNotFound);
                }
                Some(ssh)
            }
            FieldKind::Text | FieldKind::Secret | FieldKind::Url => {
                if input.ssh.is_some() {
                    return Err(ModelError::UnexpectedSshData);
                }
                None
            }
        };
        let id = input.id.unwrap_or_else(Uuid::new_v4);
        if result.iter().any(|field: &CredentialField| field.id == id) {
            return Err(ModelError::DuplicateFieldId);
        }
        result.push(CredentialField {
            id,
            label: label.to_owned(),
            value: if input.kind == FieldKind::Ssh {
                String::new()
            } else {
                input.value
            },
            kind: input.kind,
            masked: input.kind != FieldKind::Ssh && input.masked,
            ssh,
        });
    }
    Ok(result)
}

fn validated_ssh_key_name(name: &str) -> Result<String, ModelError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(ModelError::EmptySshKeyName);
    }
    if name.chars().count() > MAX_NAME_CHARS {
        return Err(ModelError::SshKeyNameTooLong);
    }
    Ok(name.to_owned())
}

fn parse_ssh_key(value: &str) -> Result<(String, String, String, bool), ModelError> {
    if value.len() > MAX_VALUE_BYTES {
        return Err(ModelError::FieldValueTooLarge);
    }
    let value = value.trim();
    let parsed =
        PrivateKey::from_openssh(value.as_bytes()).map_err(|_| ModelError::InvalidSshPrivateKey)?;
    Ok((
        value.to_owned(),
        parsed.algorithm().to_string(),
        parsed.fingerprint(HashAlg::Sha256).to_string(),
        parsed.is_encrypted(),
    ))
}

fn validated_ssh_user(value: &str) -> Result<String, ModelError> {
    let value = value.trim();
    if value.is_empty()
        || value.chars().count() > 255
        || value.chars().any(char::is_whitespace)
        || value.contains('@')
    {
        return Err(ModelError::InvalidSshUser);
    }
    Ok(value.to_owned())
}

fn validated_ssh_address(value: &str) -> Result<String, ModelError> {
    let value = value.trim();
    if value.is_empty()
        || value.chars().count() > 255
        || value.starts_with('-')
        || value.chars().any(char::is_whitespace)
        || value.contains(['@', '/'])
    {
        return Err(ModelError::InvalidSshAddress);
    }
    Ok(value.to_owned())
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

fn validate_nodes(nodes: &[Node], ssh_keys: &[SshKey]) -> Result<(), ModelError> {
    for node in nodes {
        validated_name(node.name())?;
        match node {
            Node::Group(group) => validate_nodes(&group.children, ssh_keys)?,
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
                        ssh: field.ssh,
                    })
                    .collect();
                validated_fields(fields, ssh_keys)?;
            }
        }
    }
    Ok(())
}

fn ssh_key_references(nodes: &[Node], key_id: Uuid) -> Vec<String> {
    let mut references = Vec::new();
    for node in nodes {
        match node {
            Node::Group(group) => references.extend(ssh_key_references(&group.children, key_id)),
            Node::Entry(entry) => {
                references.extend(entry.fields.iter().filter_map(|field| {
                    (field.ssh.as_ref().is_some_and(|ssh| ssh.key_id == key_id))
                        .then(|| format!("{} / {}", entry.name, field.label))
                }));
            }
        }
    }
    references
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
                    if let Some(ssh) = &mut field.ssh {
                        ssh.user.zeroize();
                        ssh.address.zeroize();
                    }
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use ssh_key::{Algorithm, LineEnding, PrivateKey, rand_core::OsRng};

    use super::*;

    fn openssh_private_key() -> String {
        PrivateKey::random(&mut OsRng, Algorithm::Ed25519)
            .unwrap()
            .to_openssh(LineEnding::LF)
            .unwrap()
            .to_string()
    }

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
            ssh: None,
        }
    }

    fn ssh_field(label: &str, key_id: Uuid) -> FieldInput {
        FieldInput {
            id: None,
            label: label.to_owned(),
            value: String::new(),
            kind: FieldKind::Ssh,
            masked: false,
            ssh: Some(SshConnection {
                user: "deploy".to_owned(),
                address: "example.invalid".to_owned(),
                port: Some(2222),
                key_id,
            }),
        }
    }

    #[test]
    fn migrates_v1_vaults_without_changing_existing_fields() {
        let mut vault: VaultData = serde_json::from_value(serde_json::json!({
            "schema_version": 1,
            "nodes": [{
                "type": "entry",
                "id": "25b94141-dff7-478b-93b0-cc268974a27b",
                "name": "Legacy",
                "fields": [{
                    "id": "a2da4cbf-1385-4138-8226-a34895145732",
                    "label": "Password",
                    "value": "preserved",
                    "kind": "secret",
                    "masked": true
                }]
            }]
        }))
        .unwrap();

        vault.migrate().unwrap();

        assert_eq!(vault.schema_version, 2);
        assert!(vault.ssh_keys.is_empty());
        assert_eq!(
            vault
                .field(
                    Uuid::parse_str("25b94141-dff7-478b-93b0-cc268974a27b").unwrap(),
                    Uuid::parse_str("a2da4cbf-1385-4138-8226-a34895145732").unwrap(),
                )
                .unwrap()
                .value,
            "preserved"
        );
    }

    #[test]
    fn reuses_and_renames_ssh_keys_without_breaking_references() {
        let mut vault = VaultData::default();
        let key_id = vault
            .add_ssh_key("Production", &openssh_private_key())
            .unwrap();
        let first = vault
            .add_entry(None, "Web", vec![ssh_field("SSH", key_id)])
            .unwrap();
        let second = vault
            .add_entry(None, "Worker", vec![ssh_field("SSH", key_id)])
            .unwrap();

        vault
            .update_ssh_key(key_id, "Production renamed", None)
            .unwrap();

        assert_eq!(vault.ssh_key(key_id).unwrap().name, "Production renamed");
        assert_eq!(
            find_entry(&vault.nodes, first).unwrap().fields[0]
                .ssh
                .as_ref()
                .unwrap()
                .key_id,
            key_id
        );
        assert_eq!(
            find_entry(&vault.nodes, second).unwrap().fields[0]
                .ssh
                .as_ref()
                .unwrap()
                .key_id,
            key_id
        );
    }

    #[test]
    fn validates_key_material_names_connections_and_reference_integrity() {
        let mut vault = VaultData::default();
        assert_eq!(
            vault.add_ssh_key("Broken", "not a key"),
            Err(ModelError::InvalidSshPrivateKey)
        );
        let key_id = vault.add_ssh_key("Shared", &openssh_private_key()).unwrap();
        assert_eq!(
            vault.add_ssh_key("shared", &openssh_private_key()),
            Err(ModelError::DuplicateSshKeyName)
        );
        let mut invalid = ssh_field("SSH", key_id);
        invalid.ssh.as_mut().unwrap().address = "-oProxyCommand=bad".to_owned();
        assert_eq!(
            vault.add_entry(None, "Invalid", vec![invalid]),
            Err(ModelError::InvalidSshAddress)
        );

        vault
            .add_entry(None, "Server", vec![ssh_field("Primary", key_id)])
            .unwrap();
        assert_eq!(
            vault.delete_ssh_key(key_id),
            Err(ModelError::SshKeyInUse("Server / Primary".to_owned()))
        );
    }

    #[test]
    fn accepts_encrypted_openssh_keys_and_records_non_secret_metadata() {
        let parsed = PrivateKey::from_openssh(openssh_private_key()).unwrap();
        let encrypted = parsed
            .encrypt(&mut OsRng, b"example passphrase")
            .unwrap()
            .to_openssh(LineEnding::LF)
            .unwrap();
        let mut vault = VaultData::default();

        let key_id = vault.add_ssh_key("Encrypted", encrypted.as_str()).unwrap();
        let key = vault.ssh_key(key_id).unwrap();

        assert!(key.encrypted);
        assert_eq!(key.algorithm, "ssh-ed25519");
        assert!(key.fingerprint.starts_with("SHA256:"));
    }

    #[test]
    fn ordinary_vault_views_redact_private_key_material() {
        let private_key = openssh_private_key();
        let mut vault = VaultData::default();
        let key_id = vault.add_ssh_key("Visible metadata", &private_key).unwrap();
        vault
            .add_entry(None, "Server", vec![ssh_field("SSH", key_id)])
            .unwrap();

        let json =
            serde_json::to_string(&crate::view::VaultView::from_data(Uuid::new_v4(), &vault))
                .unwrap();

        assert!(!json.contains("OPENSSH PRIVATE KEY"));
        assert!(!json.contains(private_key.lines().nth(1).unwrap()));
        assert!(json.contains("Visible metadata"));
        assert!(json.contains("SHA256:"));
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
                ssh: field.ssh.clone(),
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
