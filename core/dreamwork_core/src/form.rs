use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rule {
    pub tier: u8,
    pub source_key: String,
    pub target_field: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormMatch {
    pub target_field: String,
    pub value: String,
    pub tier: u8,
}

pub trait FormMatcher {
    fn match_field(&self, rules: &[Rule], extracted: &HashMap<String, String>) -> Option<FormMatch>;
}

#[derive(Debug, Default)]
pub struct RulesFirstMatcher;

impl FormMatcher for RulesFirstMatcher {
    fn match_field(&self, rules: &[Rule], extracted: &HashMap<String, String>) -> Option<FormMatch> {
        let mut candidates: Vec<&Rule> = rules
            .iter()
            .filter(|rule| extracted.contains_key(&rule.source_key))
            .collect();

        candidates.sort_by(|a, b| a.tier.cmp(&b.tier).then_with(|| a.source_key.cmp(&b.source_key)));

        let selected = candidates.first()?;
        let value = extracted.get(&selected.source_key)?.clone();

        Some(FormMatch {
            target_field: selected.target_field.clone(),
            value,
            tier: selected.tier,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn form_matcher_deterministic_tier_selects_mapped_field() {
        let matcher = RulesFirstMatcher;
        let rules = vec![
            Rule {
                tier: 2,
                source_key: "ocr.name".to_string(),
                target_field: "form.name".to_string(),
            },
            Rule {
                tier: 1,
                source_key: "manual.name".to_string(),
                target_field: "form.name".to_string(),
            },
        ];

        let mut extracted = HashMap::new();
        extracted.insert("ocr.name".to_string(), "From OCR".to_string());
        extracted.insert("manual.name".to_string(), "From Manual".to_string());

        let selected = matcher.match_field(&rules, &extracted).unwrap();

        assert_eq!(selected.target_field, "form.name");
        assert_eq!(selected.value, "From Manual");
        assert_eq!(selected.tier, 1);
    }
}
