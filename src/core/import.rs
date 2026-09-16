use serde_yaml_ng::{Mapping, Value};
use thiserror::Error;
use uuid::Uuid;

use super::{CredentialField, Entry, FieldKind, Group, Node};

const MAX_YAML_BYTES: usize = 16 * 1024 * 1024;

#[derive(Debug, Error)]
pub enum ImportError {
    #[error("YAML input is too large")]
    TooLarge,
    #[error("YAML cannot be parsed: {0}")]
    Parse(#[from] serde_yaml_ng::Error),
    #[error("the YAML root must be a mapping")]
    RootIsNotMapping,
    #[error("YAML mapping keys must be strings or scalar values")]
    InvalidKey,
}

pub fn import_yaml(source: &str) -> Result<Vec<Node>, ImportError> {
    if source.len() > MAX_YAML_BYTES {
        return Err(ImportError::TooLarge);
    }
    let value: Value = serde_yaml_ng::from_str(source)?;
    let Value::Mapping(mapping) = value else {
        return Err(ImportError::RootIsNotMapping);
    };

    mapping_to_root(&mapping)
}

fn mapping_to_root(mapping: &Mapping) -> Result<Vec<Node>, ImportError> {
    let mut nodes = Vec::new();
    let mut scalar_fields = Vec::new();

    for (key, value) in mapping {
        let key = key_to_string(key)?;
        match value {
            Value::Mapping(child) => nodes.push(mapping_to_node(key, child)?),
            _ => scalar_fields.push(field_from_value(key, value)),
        }
    }

    if !scalar_fields.is_empty() {
        nodes.insert(0, entry_node("General".to_owned(), scalar_fields));
    }
    Ok(nodes)
}

fn mapping_to_node(name: String, mapping: &Mapping) -> Result<Node, ImportError> {
    let mut children = Vec::new();
    let mut fields = Vec::new();

    for (key, value) in mapping {
        let key = key_to_string(key)?;
        match value {
            Value::Mapping(child) => children.push(mapping_to_node(key, child)?),
            _ => fields.push(field_from_value(key, value)),
        }
    }

    if children.is_empty() {
        Ok(entry_node(name, fields))
    } else {
        if !fields.is_empty() {
            children.insert(0, entry_node("General".to_owned(), fields));
        }
        Ok(Node::Group(Group {
            id: Uuid::new_v4(),
            name,
            children,
        }))
    }
}

fn entry_node(name: String, fields: Vec<CredentialField>) -> Node {
    Node::Entry(Entry {
        id: Uuid::new_v4(),
        name,
        fields,
    })
}

fn field_from_value(label: String, value: &Value) -> CredentialField {
    let value = value_to_string(value);
    let normalized = label.to_lowercase().replace('_', "-");
    let masked = is_secret_label(&normalized);
    let kind = if masked {
        FieldKind::Secret
    } else if (normalized.contains("url") || normalized.contains("addr"))
        && (value.starts_with("http://") || value.starts_with("https://"))
    {
        FieldKind::Url
    } else if value.contains('\n') {
        FieldKind::Note
    } else {
        FieldKind::Text
    };

    CredentialField {
        id: Uuid::new_v4(),
        label,
        value,
        kind,
        masked,
    }
}

fn is_secret_label(label: &str) -> bool {
    [
        "password",
        "passwd",
        "passphrase",
        "token",
        "secret",
        "api-key",
        "apikey",
        "private-key",
        "privatekey",
        "credential",
    ]
    .iter()
    .any(|needle| label.contains(needle))
}

fn key_to_string(key: &Value) -> Result<String, ImportError> {
    match key {
        Value::String(value) => Ok(value.clone()),
        Value::Bool(value) => Ok(value.to_string()),
        Value::Number(value) => Ok(value.to_string()),
        Value::Null | Value::Sequence(_) | Value::Mapping(_) | Value::Tagged(_) => {
            Err(ImportError::InvalidKey)
        }
    }
}

fn value_to_string(value: &Value) -> String {
    match value {
        Value::Null => String::new(),
        Value::Bool(value) => value.to_string(),
        Value::Number(value) => value.to_string(),
        Value::String(value) => value.clone(),
        Value::Sequence(values) => values
            .iter()
            .map(value_to_string)
            .collect::<Vec<_>>()
            .join("\n"),
        Value::Mapping(_) | Value::Tagged(_) => serde_yaml_ng::to_string(value)
            .unwrap_or_default()
            .trim()
            .to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn imports_nested_yaml_and_masks_secret_fields() {
        let source = r"
accounts:
  example:
    login: demo-user
    password: definitely-not-real
service:
  api-key: sk-example-redacted
  base-url: https://example.invalid
";

        let nodes = import_yaml(source).unwrap();
        assert_eq!(nodes.len(), 2);

        let Node::Group(accounts) = &nodes[0] else {
            panic!("accounts should be a group");
        };
        let Node::Entry(example) = &accounts.children[0] else {
            panic!("example should be an entry");
        };
        assert!(!example.fields[0].masked);
        assert!(example.fields[1].masked);

        let Node::Entry(service) = &nodes[1] else {
            panic!("service should be an entry");
        };
        assert!(service.fields[0].masked);
        assert_eq!(service.fields[1].kind, FieldKind::Url);
    }

    #[test]
    fn mixed_mappings_use_a_general_entry() {
        let source = r"
project:
  owner: demo
  production:
    url: https://example.invalid
";
        let nodes = import_yaml(source).unwrap();
        let Node::Group(project) = &nodes[0] else {
            panic!("project should be a group");
        };
        assert_eq!(project.children[0].name(), "General");
        assert_eq!(project.children[1].name(), "production");
    }
}
