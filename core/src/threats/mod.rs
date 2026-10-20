//! Threat detection: signatures, heuristics, startup persistence, Defender hand-off and quarantine.

pub mod authenticode;
pub mod defender;
pub mod heuristics;
pub mod quarantine;
pub mod scan;
pub mod signatures;
pub mod startup;

use serde::Serialize;

/// One piece of evidence. Weights add up to a 0-100 score.
#[derive(Serialize, Clone, Debug, PartialEq)]
pub struct Reason {
    pub code: String,
    pub label: String,
    pub weight: i32,
}

impl Reason {
    pub fn new(code: &str, label: impl Into<String>, weight: i32) -> Self {
        Self { code: code.into(), label: label.into(), weight }
    }
}

pub fn score(reasons: &[Reason]) -> i32 {
    if reasons.iter().any(|r| r.code == "signature" || r.code == "defender") {
        return 100;
    }
    reasons.iter().map(|r| r.weight).sum::<i32>().clamp(0, 100)
}

pub fn severity(score: i32) -> &'static str {
    match score {
        70.. => "high",
        40..=69 => "medium",
        1..=39 => "low",
        _ => "none",
    }
}
