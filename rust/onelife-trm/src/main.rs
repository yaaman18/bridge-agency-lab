#![allow(dead_code)]
//! `onelife-trm` Phase 3 minimal 4-seam bed skeleton CLI & verification test suite.
//! Scope: validates species_spec TOML parsing, 4-seam bed invariants, S68 C4 radio conversion,
//! and static `aarch64-unknown-linux-musl` cross-build readiness.
//! Rust multi-species generality remains deferred until Phase 6 passes a 2nd real species through this bed.

mod bed;
mod c4_radio;
mod sha256;
mod spec;

use std::env;
use std::path::Path;
use std::process;

use crate::spec::SpeciesSpec;

fn main() {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(|s| s.as_str()) {
        Some("verify-spec") => {
            let Some(path) = args.get(2) else {
                eprintln!("usage: onelife-trm verify-spec <species_spec.toml>");
                process::exit(2);
            };
            match SpeciesSpec::from_toml_file(Path::new(path)) {
                Ok(sp) => {
                    println!(
                        "OK species_id={} spec_sha256={} mapping_spec_hash={} phenomenal_claim={}",
                        sp.species_id, sp.spec_sha256, sp.mapping_spec_hash, sp.phenomenal_claim
                    );
                }
                Err(e) => {
                    eprintln!("ERR {e}");
                    process::exit(1);
                }
            }
        }
        Some("version") | None => {
            println!("onelife-trm 0.1.0 (phase3-bed-skeleton; phenomenal_claim=not_certified)");
        }
        Some(other) => {
            eprintln!("unknown subcommand: {other}");
            process::exit(2);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;
    use std::path::PathBuf;

    use crate::bed::*;
    use crate::c4_radio::*;
    use crate::sha256::sha256_hex;
    use crate::spec::{SpecError, SpeciesSpec};

    #[derive(Clone)]
    struct DummyState {
        energy: i64,
        spores: usize,
        emit_spore_at: Option<u64>,
    }

    struct DummyAdapter {
        spec: SpeciesSpec,
        organ_type: String,
        inject_bad_out: bool,
        ops_override: Option<u64>,
        free_dormancy: bool,
    }

    impl SpeciesAdapter for DummyAdapter {
        type State = DummyState;

        fn spec(&self) -> &SpeciesSpec {
            &self.spec
        }

        fn state_digest(&self, st: &Self::State) -> String {
            let mut bytes = Vec::new();
            bytes.extend_from_slice(&st.energy.to_le_bytes());
            bytes.extend_from_slice(&(st.spores as u64).to_le_bytes());
            sha256_hex(&bytes)
        }

        fn step_species(
            &self,
            mut st: Self::State,
            si: &StampedInput,
            _budget: Budget,
        ) -> StepOutcome<Self::State> {
            let g1 = match si.ports.get("g1") {
                Some(PortVal::F64(v)) => *v,
                _ => 0.0,
            };
            st.energy += if g1 > 0.0 { 1 } else { -2 };
            let alive = st.energy > 0;
            let spore_req = if st.emit_spore_at == Some(si.step) {
                st.spores += 1;
                Some(format!("spore-{}", si.step))
            } else {
                None
            };
            let dorm_paid = if self.free_dormancy {
                0.0
            } else {
                (st.spores as f64) * self.spec.dormancy_upkeep_rate
            };
            let mut ports = BTreeMap::new();
            ports.insert("act_patch_1".into(), PortVal::I64(1));
            ports.insert("act_patch_2".into(), PortVal::I64(0));
            ports.insert("alive".into(), PortVal::Bool(alive));
            ports.insert("constituents".into(), PortVal::I64(st.energy.max(0)));
            if self.inject_bad_out {
                ports.insert("secret_sidechannel".into(), PortVal::I64(1));
            }
            StepOutcome {
                next_state: st,
                output: DeclaredOutput {
                    ports,
                    organ_type: self.organ_type.clone(),
                },
                cost: StepCost {
                    ops_used: self.ops_override.unwrap_or(100),
                    upkeep_paid: 0.01,
                    act_cost: 0.004,
                    dormancy_upkeep_paid: dorm_paid,
                },
                alive,
                spore_req,
            }
        }
    }

    fn seam_dir() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("experiments")
            .join("aue_seam")
    }

    fn mk_input(step: u64, g1: f64, g2: f64, refs: Vec<(String, f64)>) -> StampedInput {
        let mut ports = BTreeMap::new();
        ports.insert("g1".into(), PortVal::F64(g1));
        ports.insert("g2".into(), PortVal::F64(g2));
        StampedInput {
            step,
            ports,
            event_refs: refs,
        }
    }

    #[test]
    fn test_sha256_nist_vector() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn test_species_toml_parity_with_julia_sha256() {
        let sp_a = SpeciesSpec::from_toml_file(&seam_dir().join("species_aue_a.toml")).unwrap();
        assert_eq!(sp_a.species_id, "AUE-A-OneLife-L2");
        assert_eq!(
            sp_a.spec_sha256,
            "b21bc008fb3bd3021059aed58c375df04d942ac8f07272556400e4900a89c1e8"
        );
        assert_eq!(
            sp_a.mapping_spec_hash,
            "f69709ffc7722385b183fbadf6ab52466af64b002210e6d245068cb08d9fd61c"
        );

        let sp_b = SpeciesSpec::from_toml_file(&seam_dir().join("species_aue_b.toml")).unwrap();
        assert_eq!(sp_b.species_id, "AUE-B-Nesting-CPC");
        assert_eq!(
            sp_b.spec_sha256,
            "815ea90809794528a6950b38f59f63095a7cbf0939ebd5f0772f1dc6792b2c84"
        );
    }

    #[test]
    fn test_spec_rejects_certified_phenomenal_claim_and_free_dormancy() {
        let bad_claim = b"species_id=\"X\"\nspec_version=\"0.1\"\nsubstrate=\"s\"\nindividual_boundary=\"b\"\nallowed_organ_types=[\"a\"]\nmapping_spec_hash=\"h\"\nphenomenal_claim=\"certified\"\n[ports]\ninputs=[\"g1\"]\noutputs=[\"alive\"]\n[budget]\nstep_granularity_sec=10.0\nops_per_step=10\nops_per_hour=100\n[dormancy]\nupkeep_rate_per_slot=0.01\nmax_slots=1\n";
        assert!(matches!(
            SpeciesSpec::from_toml_bytes(bad_claim),
            Err(SpecError::Invariant(_))
        ));

        let free_dorm = b"species_id=\"X\"\nspec_version=\"0.1\"\nsubstrate=\"s\"\nindividual_boundary=\"b\"\nallowed_organ_types=[\"a\"]\nmapping_spec_hash=\"h\"\nphenomenal_claim=\"not_certified\"\n[ports]\ninputs=[\"g1\"]\noutputs=[\"alive\"]\n[budget]\nstep_granularity_sec=10.0\nops_per_step=10\nops_per_hour=100\n[dormancy]\nupkeep_rate_per_slot=0.0\nmax_slots=1\n";
        assert!(matches!(
            SpeciesSpec::from_toml_bytes(free_dorm),
            Err(SpecError::Invariant(_))
        ));
    }

    #[test]
    fn test_bed_guards_replay_3way_termination_and_doublespend() {
        let spec = SpeciesSpec::from_toml_file(&seam_dir().join("species_aue_a.toml")).unwrap();
        let ad = DummyAdapter {
            spec: spec.clone(),
            organ_type: "L2_circuit_bin3".into(),
            inject_bad_out: false,
            ops_override: None,
            free_dormancy: false,
        };

        // 1. Pre-death spore + metabolic death + 0 commits after death + full text replay + lineage child
        let inputs = vec![
            mk_input(0, 1.0, 0.0, vec![]), // energy 2 -> 3, emit spore
            mk_input(1, 0.0, 0.0, vec![]), // energy 3 -> 1
            mk_input(2, 0.0, 0.0, vec![]), // energy 1 -> -1 (DEAD!)
            mk_input(3, 1.0, 0.0, vec![]), // MUST NOT BE EXECUTED (0 commits after death)
            mk_input(4, 1.0, 0.0, vec![]),
        ];
        let res = run_species(
            &ad,
            "ind-meta",
            DummyState {
                energy: 2,
                spores: 0,
                emit_spore_at: Some(0),
            },
            &inputs,
            None,
        )
        .unwrap();
        assert_eq!(res.ledger.termination, TerminationCode::MetabolicOrOrgDeath);
        assert_eq!(res.ledger.death_step, Some(2));
        assert_eq!(res.ledger.steps_completed, 3);
        assert_eq!(
            res.audit
                .rows
                .iter()
                .filter(|r| r.kind == "commit" && r.step > 2)
                .count(),
            0
        );
        let rep = replay_from_audit(
            &ad,
            DummyState {
                energy: 2,
                spores: 0,
                emit_spore_at: Some(0),
            },
            &res.audit,
        )
        .unwrap();
        assert_eq!(rep.audit.rows.last().unwrap().hash, res.audit.rows.last().unwrap().hash);
        let child = germinate_lineage_child(&res.ledger, &res.audit, "spore-0", "child-1").unwrap();
        assert!(!child.same_individual && child.lineage_child && child.verified_pre_death);
        assert!(matches!(
            attempt_post_death_spore(&res.ledger, &res.audit, "illegal-rescue"),
            Err(SeamError::ProhibitedRescueError(_))
        ));

        // 2. Tamper 1 byte in audit input row -> replay rejects
        let mut tampered = res.audit.clone();
        tampered.rows[1].payload.push(' ');
        assert!(matches!(
            replay_from_audit(
                &ad,
                DummyState {
                    energy: 2,
                    spores: 0,
                    emit_spore_at: Some(0),
                },
                &tampered
            ),
            Err(SeamError::ChainIntegrityError(_))
        ));

        // 3. Non-metabolic verified + Unexplained truncation full replay
        let short_in = vec![mk_input(0, 1.0, 0.0, vec![])];
        let hw = run_species(
            &ad,
            "ind-hw",
            DummyState {
                energy: 5,
                spores: 0,
                emit_spore_at: None,
            },
            &short_in,
            Some((
                TerminationCode::NonMetabolicTerminationVerified,
                "boot_id=851197f9;dmesg=power_loss",
            )),
        )
        .unwrap();
        let hw_rep = replay_from_audit(
            &ad,
            DummyState {
                energy: 5,
                spores: 0,
                emit_spore_at: None,
            },
            &hw.audit,
        )
        .unwrap();
        assert_eq!(hw_rep.ledger.termination, TerminationCode::NonMetabolicTerminationVerified);
        assert_eq!(hw_rep.audit.rows.last().unwrap().hash, hw.audit.rows.last().unwrap().hash);

        let tr = run_species(
            &ad,
            "ind-tr",
            DummyState {
                energy: 5,
                spores: 0,
                emit_spore_at: None,
            },
            &short_in,
            Some((TerminationCode::UnexplainedTruncation, "")),
        )
        .unwrap();
        let tr_rep = replay_from_audit(
            &ad,
            DummyState {
                energy: 5,
                spores: 0,
                emit_spore_at: None,
            },
            &tr.audit,
        )
        .unwrap();
        assert_eq!(tr_rep.ledger.termination, TerminationCode::UnexplainedTruncation);

        // 4. Negative controls: undeclared port, bad organ, budget overflow, rolling 1h window, free dormancy
        let ad_bad_out = DummyAdapter {
            spec: spec.clone(),
            organ_type: "L2_circuit_bin3".into(),
            inject_bad_out: true,
            ops_override: None,
            free_dormancy: false,
        };
        assert!(matches!(
            run_species(&ad_bad_out, "n1", DummyState { energy: 5, spores: 0, emit_spore_at: None }, &short_in, None),
            Err(SeamError::PortViolation(_))
        ));

        let ad_bad_organ = DummyAdapter {
            spec: spec.clone(),
            organ_type: "unauthorized_llm".into(),
            inject_bad_out: false,
            ops_override: None,
            free_dormancy: false,
        };
        assert!(matches!(
            run_species(&ad_bad_organ, "n2", DummyState { energy: 5, spores: 0, emit_spore_at: None }, &short_in, None),
            Err(SeamError::SpeciesBoundaryViolation(_))
        ));

        let ad_over_step = DummyAdapter {
            spec: spec.clone(),
            organ_type: "L2_circuit_bin3".into(),
            inject_bad_out: false,
            ops_override: Some(10001),
            free_dormancy: false,
        };
        assert!(matches!(
            run_species(&ad_over_step, "n3", DummyState { energy: 5, spores: 0, emit_spore_at: None }, &short_in, None),
            Err(SeamError::BudgetViolation(_))
        ));

        let mut roll_spec = spec.clone();
        roll_spec.step_granularity_sec = 1000.0;
        roll_spec.budget_per_step = 200;
        roll_spec.wall_budget_per_hour = 360;
        let ad_roll = DummyAdapter {
            spec: roll_spec,
            organ_type: "L2_circuit_bin3".into(),
            inject_bad_out: false,
            ops_override: Some(100),
            free_dormancy: false,
        };
        let in3 = vec![
            mk_input(0, 1.0, 0.0, vec![]),
            mk_input(1, 1.0, 0.0, vec![]),
            mk_input(2, 1.0, 0.0, vec![]),
        ];
        assert!(run_species(&ad_roll, "r3", DummyState { energy: 5, spores: 0, emit_spore_at: None }, &in3, None).is_ok());
        let mut in4 = in3.clone();
        in4.push(mk_input(3, 1.0, 0.0, vec![]));
        assert!(matches!(
            run_species(&ad_roll, "r4", DummyState { energy: 5, spores: 0, emit_spore_at: None }, &in4, None),
            Err(SeamError::BudgetViolation(_))
        ));

        let ad_free_dorm = DummyAdapter {
            spec: spec.clone(),
            organ_type: "L2_circuit_bin3".into(),
            inject_bad_out: false,
            ops_override: None,
            free_dormancy: true,
        };
        assert!(matches!(
            run_species(&ad_free_dorm, "n5", DummyState { energy: 5, spores: 0, emit_spore_at: Some(0) }, &short_in, None),
            Err(SeamError::DormancyAccountingViolation(_))
        ));

        // 5. Shared-medium double-spend parsed from audit text
        let mut med = SharedMediumAudit::new("m1");
        med.record_event("ev-0", 0, 5.0).unwrap();
        let r1 = run_species(
            &ad,
            "s1",
            DummyState { energy: 5, spores: 0, emit_spore_at: None },
            &[mk_input(0, 3.0, 0.0, vec![("ev-0".into(), 3.0)])],
            None,
        )
        .unwrap();
        let r2_ok = run_species(
            &ad,
            "s2",
            DummyState { energy: 5, spores: 0, emit_spore_at: None },
            &[mk_input(0, 2.0, 0.0, vec![("ev-0".into(), 2.0)])],
            None,
        )
        .unwrap();
        assert!(med.verify(&[&r1.audit, &r2_ok.audit], 1e-12).is_ok());

        let r2_ds = run_species(
            &ad,
            "s2-ds",
            DummyState { energy: 5, spores: 0, emit_spore_at: None },
            &[mk_input(0, 3.0, 0.0, vec![("ev-0".into(), 3.0)])],
            None,
        )
        .unwrap();
        assert!(matches!(
            med.verify(&[&r1.audit, &r2_ds.audit], 1e-12),
            Err(SeamError::DoubleSpendViolation(_))
        ));
    }

    #[test]
    fn test_s68_rounding_stale_and_rand_u64() {
        // Half-integer round-half-to-even (matches Julia Base.round)
        assert_eq!(round_yield_s68(0.5), 0.0);
        assert_eq!(round_yield_s68(1.5), 2.0);
        assert_eq!(round_yield_s68(2.5), 2.0);
        assert_eq!(round_yield_s68(3.5), 4.0);
        assert_eq!(round_yield_s68(4.5), 4.0);
        assert_eq!(round_yield_s68(2.5f64.next_up()), 3.0);
        assert_eq!(round_yield_s68(2.5f64.next_down()), 2.0);

        // Incomplete trailing line & fail>0 skipped cleanly
        let raw = b"pi_s\tboot\tuptime_s\tw_n\tw_sum\tb_n\tt_mc\tfail\n1794828000\tb1\t100.0\t5\t300.0\t3\t45000\t0\n1794828030\tb1\t130.0\t5\tNA\t3\t45000\t0\n1794828060\tb1\t160.0\t5\t310.0\t4\t45000\t1\n1794828090\tb1\t190.0\t5\t320.0";
        let obs = parse_last_valid_ambient(raw).unwrap();
        assert_eq!(obs.uptime_s, 100.0);
        assert_eq!(obs.w_sum, 300.0);

        // Stale tracker: streak 1..13 not stale, streak 14 stale; NTP pi_s jump ignored; boot change resets
        let mut tr = StaleTracker::default();
        assert!(tr.observe(None, 0.0));
        for k in 0..13 {
            // Even if pi_s jumped +/-3600s, tracker only reads (boot, uptime_s) + mono
            let mut o = obs.clone();
            o.pi_s = (1794828000 + if k % 2 == 0 { 3600 } else { -3600 }).to_string();
            assert!(!tr.observe(Some(&o), (k as f64) * 10.0), "step {k} should not be stale");
        }
        assert!(tr.observe(Some(&obs), 130.0), "14th consecutive same row must be stale");

        // Boot change resets streak cleanly
        let mut reboot_obs = obs.clone();
        reboot_obs.boot = "b2".into();
        reboot_obs.uptime_s = 10.0;
        assert!(!tr.observe(Some(&reboot_obs), 140.0));
        assert_eq!(tr.same_row_streak, 1);

        // Deterministic rand_u64 changes on 1-bit tamper of raw_line_sha256
        let r_a = derive_rand_u64(GENESIS_HASH, 0, &obs.raw_line_sha256, false);
        let mut bad_sha = obs.raw_line_sha256.clone();
        bad_sha.replace_range(0..1, if bad_sha.starts_with('0') { "1" } else { "0" });
        let r_b = derive_rand_u64(GENESIS_HASH, 0, &bad_sha, false);
        assert_ne!(r_a, r_b);

        // C4 yield calculation with precomputed 1000-entry sine table:
        // Note: sin(0) == 0.0 -> 2.5 rounds-to-even to 2.0, while sin(pi) == +1.2246e-16 -> 2.5+eps rounds to 3.0!
        // This exact half-integer sensitivity is why S68 r2 freezes SIN_TABLE_1000 raw f64 bits in the audit header.
        let mut sin_tbl = [0.0f64; 1000];
        for i in 0..1000 {
            sin_tbl[i] = (2.0 * std::f64::consts::PI * (i as f64) / 1000.0).sin();
        }
        let (g1_stale, g2_stale) = compute_c4_yields(&sin_tbl, 0, 999.0, 999.0, true);
        assert_eq!((g1_stale, g2_stale), (2.0, 3.0));
        // With exact symmetric 0.0 at index 500, both patches hit exact 2.5 -> round-to-even 2.0:
        sin_tbl[500] = 0.0;
        let (g1_sym, g2_sym) = compute_c4_yields(&sin_tbl, 0, 999.0, 999.0, true);
        assert_eq!((g1_sym, g2_sym), (2.0, 2.0));
    }
}
