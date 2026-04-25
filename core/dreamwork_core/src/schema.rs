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

#[cfg(test)]
mod tests {
    use super::*;

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
