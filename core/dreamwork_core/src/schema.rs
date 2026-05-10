use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MappingPlan {
    pub mappings: Vec<FieldMapping>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FieldMapping {
    pub source_key: String,
    pub target_field: String,
    pub op: MappingOp,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MappingOp {
    Copy,
    Trim,
    Unsupported(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ValidationError {
    UnsupportedOperation(String),
}

pub trait MappingPlanValidator {
    fn validate(&self, plan: &MappingPlan) -> Result<(), ValidationError>;
}

#[derive(Debug, Default)]
pub struct DefaultMappingPlanValidator;

impl MappingPlanValidator for DefaultMappingPlanValidator {
    fn validate(&self, plan: &MappingPlan) -> Result<(), ValidationError> {
        for mapping in &plan.mappings {
            if let MappingOp::Unsupported(name) = &mapping.op {
                return Err(ValidationError::UnsupportedOperation(name.clone()));
            }
        }

        Ok(())
    }
}

/// Apply a validated mapping plan: read each `source_key` from `sources` and write `target_field`.
///
/// Missing sources become empty strings. Runs [`DefaultMappingPlanValidator::validate`] first.
pub fn apply_mapping_plan(
    plan: &MappingPlan,
    sources: &HashMap<String, String>,
) -> Result<HashMap<String, String>, ValidationError> {
    DefaultMappingPlanValidator.validate(plan)?;
    let mut out = HashMap::new();
    for mapping in &plan.mappings {
        let raw = sources
            .get(&mapping.source_key)
            .cloned()
            .unwrap_or_default();
        let value = match &mapping.op {
            MappingOp::Copy => raw,
            MappingOp::Trim => raw.trim().to_string(),
            MappingOp::Unsupported(name) => {
                return Err(ValidationError::UnsupportedOperation(name.clone()));
            }
        };
        out.insert(mapping.target_field.clone(), value);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apply_mapping_plan_copy_and_trim() {
        let mut src = HashMap::new();
        src.insert("k1".into(), "  x  ".into());
        let plan = MappingPlan {
            mappings: vec![
                FieldMapping {
                    source_key: "k1".into(),
                    target_field: "t1".into(),
                    op: MappingOp::Copy,
                },
                FieldMapping {
                    source_key: "k1".into(),
                    target_field: "t2".into(),
                    op: MappingOp::Trim,
                },
            ],
        };
        let out = apply_mapping_plan(&plan, &src).unwrap();
        assert_eq!(out.get("t1").map(String::as_str), Some("  x  "));
        assert_eq!(out.get("t2").map(String::as_str), Some("x"));
    }

    #[test]
    fn mapping_plan_validator_rejects_unsupported_ops() {
        let validator = DefaultMappingPlanValidator;
        let plan = MappingPlan {
            mappings: vec![FieldMapping {
                source_key: "ocr.full_name".to_string(),
                target_field: "form.applicant_name".to_string(),
                op: MappingOp::Unsupported("regex_replace".to_string()),
            }],
        };

        let result = validator.validate(&plan);

        assert_eq!(
            result,
            Err(ValidationError::UnsupportedOperation(
                "regex_replace".to_string()
            ))
        );
    }
}
