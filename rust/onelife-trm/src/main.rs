#![allow(dead_code)]
//! `onelife-trm` Phase 3 minimal 4-seam bed skeleton CLI & verification test suite.
//! Scope: validates species_spec TOML parsing, 4-seam bed invariants, S68 C4 radio conversion,
//! and static `aarch64-unknown-linux-musl` cross-build readiness.
//! Rust multi-species generality remains deferred until Phase 6 passes a 2nd real species through this bed.

mod bed;
mod c4_radio;
mod head_c2;
mod recovery;
mod sha256;
mod sin_table;
mod spec;
mod trm_infer;

use std::env;
use std::fs;
use std::path::Path;
use std::process;

use crate::sin_table::{verify_sin_table_sha256, SIN_TABLE_SHA256};
use crate::spec::SpeciesSpec;
use crate::trm_infer::run_trm_bundle;

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
        Some("verify-sin") => {
            let got = verify_sin_table_sha256();
            if got == SIN_TABLE_SHA256 {
                println!("OK sin_table_sha256={got}");
            } else {
                eprintln!("ERR sin_table_sha256 mismatch: got={got} expected={SIN_TABLE_SHA256}");
                process::exit(1);
            }
        }
        Some("run-trm") => {
            let (Some(bundle_path), Some(out_path)) = (args.get(2), args.get(3)) else {
                eprintln!("usage: onelife-trm run-trm <bundle.bin> <out.bin>");
                process::exit(2);
            };
            let bytes = match fs::read(bundle_path) {
                Ok(b) => b,
                Err(e) => {
                    eprintln!("read {bundle_path}: {e}");
                    process::exit(2);
                }
            };
            match run_trm_bundle(&bytes) {
                Ok(out) => {
                    if let Err(e) = fs::write(out_path, &out) {
                        eprintln!("write {out_path}: {e}");
                        process::exit(1);
                    }
                    println!("OK trm_out_sha256={}", sha256::sha256_hex(&out));
                }
                Err(e) => {
                    eprintln!("ERR {e}");
                    process::exit(2);
                }
            }
        }
        Some("version") | None => {
            println!("onelife-trm 0.1.0 (phase3-bed+trm+c2+s68; phenomenal_claim=not_certified)");
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

    #[test]
    fn test_s67_head_c2_grad_boundaries_and_accounting() {
        use crate::head_c2::*;

        // G-C2-GRAD: 49 grid points (l8, l7) x Y in {0, 1} = 98 points vs Float64 central diff (h_fd = 1e-6)
        let grid: [f64; 7] = [-10.0, -1.0, -1e-4, 0.0, 1e-4, 1.0, 10.0];
        let h_fd = 1e-6f64;
        let s64 = |x: f64| if x >= 0.0 { x + 1.0 } else { 1.0 / (1.0 - x) };
        let loss64 = |l8: f64, l7: f64, y: f64| {
            let p = s64(l8) / (s64(l8) + s64(l7));
            -y * p.ln() - (1.0 - y) * (1.0 - p).ln()
        };
        let mut max_err = 0.0f64;
        for &l8 in &grid {
            for &l7 in &grid {
                for &y in &[0.0f64, 1.0f64] {
                    let p = s64(l8) / (s64(l8) + s64(l7));
                    let gl8 = (p - y) / (1.0 + l8.abs());
                    let gl7 = (y - p) / (1.0 + l7.abs());
                    let num8 = (loss64(l8 + h_fd, l7, y) - loss64(l8 - h_fd, l7, y)) / (2.0 * h_fd);
                    let num7 = (loss64(l8, l7 + h_fd, y) - loss64(l8, l7 - h_fd, y)) / (2.0 * h_fd);
                    let e8 = (gl8 - num8).abs();
                    let e7 = (gl7 - num7).abs();
                    if e8 > max_err { max_err = e8; }
                    if e7 > max_err { max_err = e7; }
                }
            }
        }
        assert!(max_err <= 1e-6, "G-C2-GRAD max_err={max_err} > 1e-6");

        // G-C2-ACCOUNT: (a) normal update, (b) upkeep shortfall -> 0.875 fade, (c) budget skip -> no fade, (d) death -> frozen
        let w0 = HeadWeights {
            w8: [0.25f32; HIDDEN],
            w7: [-0.25f32; HIDDEN],
            we: [0.125f32; HIDDEN],
            be: 0.0f32,
        };
        let h = [0.5f32; HIDDEN];
        let mut head = HeadC2::new(w0.clone(), 0.03125f32).unwrap();
        let pred = head.predict(&h);
        assert!(pred.p > 0.0 && pred.p < 1.0 && pred.e > 0.0 && pred.e < 1.0);

        // Updated step changes weights
        let act_u = head.post_step_update(true, true, true, &h, pred, false).unwrap();
        assert_eq!(act_u, HeadStepAction::Updated);
        assert_ne!(head.w.to_le_bytes(), w0.to_le_bytes());

        // Budget skip does NOT change weights (no fade)
        let snap_after_u = head.w.to_le_bytes();
        let act_b = head.post_step_update(true, true, false, &h, pred, false).unwrap();
        assert_eq!(act_b, HeadStepAction::SkippedOnBudget);
        assert_eq!(head.w.to_le_bytes(), snap_after_u);

        // Death freezes weights completely (even if upkeep_paid_full=false)
        let act_d = head.post_step_update(false, false, false, &h, pred, false).unwrap();
        assert_eq!(act_d, HeadStepAction::FrozenOnDeath);
        assert_eq!(head.w.to_le_bytes(), snap_after_u);

        // Upkeep shortfall fades toward w0 by exact 0.875f32
        let before_fade_w8_0 = head.w.w8[0];
        let act_f = head.post_step_update(true, false, true, &h, pred, false).unwrap();
        assert_eq!(act_f, HeadStepAction::FadedOnUpkeepShortfall);
        let expected_w8_0 = w0.w8[0] + 0.875f32 * (before_fade_w8_0 - w0.w8[0]);
        assert_eq!(head.w.w8[0].to_bits(), expected_w8_0.to_bits());

        // NaN injection is never masked by clamp -> NonFiniteWeightError
        let mut h_nan = [0.5f32; HIDDEN];
        h_nan[3] = f32::NAN;
        let res_nan = head.post_step_update(true, true, true, &h_nan, pred, true);
        assert!(res_nan.is_err(), "NaN must trigger NonFiniteWeightError");
    }

    #[test]
    fn test_head_c2_refactor_layout_fade_and_error_order() {
        use crate::head_c2::*;
        let mk = |s: f32| {
            let mut w = HeadWeights { w8: [0.0; HIDDEN], w7: [0.0; HIDDEN], we: [0.0; HIDDEN], be: 0.37 * s };
            for k in 0..HIDDEN {
                w.w8[k] = s * (k as f32 * 0.11 - 1.3);
                w.w7[k] = s * (0.7 - k as f32 * 0.05);
                w.we[k] = s * ((k * k) as f32 * 0.003 - 0.4);
            }
            w
        };
        let (w0, w) = (mk(1.0), mk(-2.5));
        // to_le_bytes: w8[0..32], w7[0..32], we[0..32], be, each little-endian (the layout before the refactor)
        let mut want = Vec::new();
        for v in w.w8.iter().chain(w.w7.iter()).chain(w.we.iter()) {
            want.extend_from_slice(&v.to_le_bytes());
        }
        want.extend_from_slice(&w.be.to_le_bytes());
        assert_eq!(w.to_le_bytes().to_vec(), want);
        // fade: all 97 entries bit-identical to w0 + 0.875 * (w - w0), clamped to +-16
        let mut head = HeadC2::new(w0.clone(), 0.01).unwrap();
        head.w = w.clone();
        let h = [0.0f32; HIDDEN];
        let pred = head.predict(&h);
        assert_eq!(head.post_step_update(true, false, true, &h, pred, true).unwrap(), HeadStepAction::FadedOnUpkeepShortfall);
        let f = |a: f32, b: f32| (b + 0.875f32 * (a - b)).clamp(-16.0, 16.0);
        for k in 0..HIDDEN {
            assert_eq!(head.w.w8[k].to_bits(), f(w.w8[k], w0.w8[k]).to_bits());
            assert_eq!(head.w.w7[k].to_bits(), f(w.w7[k], w0.w7[k]).to_bits());
            assert_eq!(head.w.we[k].to_bits(), f(w.we[k], w0.we[k]).to_bits());
        }
        assert_eq!(head.w.be.to_bits(), f(w.be, w0.be).to_bits());
        // check_finite: the first non-finite entry in the order w8, w7, we, be is named
        let mut bad = w0.clone();
        bad.we[3] = f32::NAN;
        bad.w7[5] = f32::INFINITY;
        assert_eq!(bad.check_finite().unwrap_err().0, "w7[5] non-finite: inf");
        bad.w7[5] = 0.0;
        assert_eq!(bad.check_finite().unwrap_err().0, "we[3] non-finite: NaN");
        bad.we[3] = 0.0;
        bad.be = f32::NEG_INFINITY;
        assert_eq!(bad.check_finite().unwrap_err().0, "be non-finite: -inf");
    }

    #[test]
    fn test_s68_power_loss_recovery_cases_a_to_d() {
        use crate::recovery::*;

        let hdr = "1|header|0|id=a|0000\n";
        let in0 = "2|input|0|g1=f64:3|aaaa\n";
        let cm0 = "3|commit|0|state_sha=bbbb|cccc\n";
        let in1 = "4|input|1|g1=f64:4|dddd\n";

        // Case A: input(1) fsynced, run still at step 1 -> execute step 1 once with stamped input
        let audit_a = format!("{hdr}{in0}{cm0}{in1}");
        assert_eq!(
            plan_recovery(1, audit_a.as_bytes()).unwrap(),
            RecoveryAction::ExecuteStampedInputOnce {
                step: 1,
                raw_line: in1.trim_end().to_string()
            }
        );

        // Case B: run already atomic-renamed to step 2, commit(1) missing -> emit commit(1) then proceed to 2
        assert_eq!(
            plan_recovery(2, audit_a.as_bytes()).unwrap(),
            RecoveryAction::EmitMissingCommitFromRun {
                step: 1,
                next_step: 2
            }
        );

        // Case C: commit(0) fsynced, run at step 1 -> resume cleanly at step 1
        let audit_c = format!("{hdr}{in0}{cm0}");
        assert_eq!(
            plan_recovery(1, audit_c.as_bytes()).unwrap(),
            RecoveryAction::ResumeClean { next_step: 1 }
        );

        // Case D: partial non-LF fragment -> truncate partial & acquire run_step
        let audit_d = format!("{hdr}{in0}{cm0}4|input|1|g1=f64:");
        assert_eq!(
            plan_recovery(1, audit_d.as_bytes()).unwrap(),
            RecoveryAction::TruncatePartialAndAcquire {
                next_step: 1,
                fragment_len: "4|input|1|g1=f64:".len()
            }
        );

        // R1: a complete (LF-terminated) line that is not header/input/commit is an error, not a fragment
        let audit_bad = format!("{hdr}{in0}{cm0}4|garbage\n");
        assert!(plan_recovery(1, audit_bad.as_bytes()).is_err());
        // R9 (codex): a malformed complete line followed by an unterminated fragment is also an error,
        // and planning never changes the bytes it was given
        let audit_bad_frag = format!("{hdr}{in0}{cm0}4|garbage\n5|commit|1|st");
        let before = audit_bad_frag.clone().into_bytes();
        assert!(plan_recovery(1, &before).is_err());
        assert_eq!(before, audit_bad_frag.as_bytes());

        // R2: the fragment length counts raw bytes (a lone 0xff is 1 byte, 3 bytes after lossy UTF-8)
        let mut audit_ff = format!("{hdr}{in0}{cm0}").into_bytes();
        audit_ff.push(0xff);
        assert_eq!(
            plan_recovery(1, &audit_ff).unwrap(),
            RecoveryAction::TruncatePartialAndAcquire {
                next_step: 1,
                fragment_len: 1
            }
        );

        // R3: input(1) complete, a partial commit(1) after it, run still at 1 -> discard the fragment, then Case A
        // with the stamped input(1) (no second input(1) is acquired)
        let audit_ad = format!("{hdr}{in0}{cm0}{in1}5|commit|1|st");
        assert_eq!(
            plan_recovery(1, audit_ad.as_bytes()).unwrap(),
            RecoveryAction::TruncatePartialThen {
                fragment_len: "5|commit|1|st".len(),
                then: Box::new(RecoveryAction::ExecuteStampedInputOnce {
                    step: 1,
                    raw_line: in1.trim_end().to_string()
                })
            }
        );
        // ... and with run already at 2 -> discard, then Case B
        assert_eq!(
            plan_recovery(2, audit_ad.as_bytes()).unwrap(),
            RecoveryAction::TruncatePartialThen {
                fragment_len: "5|commit|1|st".len(),
                then: Box::new(RecoveryAction::EmitMissingCommitFromRun {
                    step: 1,
                    next_step: 2
                })
            }
        );
        // a fragment after commit(0) with an inconsistent run step is an error (it used to be acquired blindly)
        assert!(plan_recovery(5, audit_d.as_bytes()).is_err());
        // codex I-R P1: step u64::MAX must not wrap to 0 (input and commit, with and without a fragment)
        let mx = u64::MAX;
        let audit_cmax = format!("{hdr}9|commit|{mx}|st|h\n");
        assert!(plan_recovery(0, audit_cmax.as_bytes()).is_err());
        assert!(plan_recovery(0, format!("{audit_cmax}x").as_bytes()).is_err());
        let audit_imax = format!("{hdr}9|input|{mx}|g1=f64:1|h\n");
        assert!(plan_recovery(0, audit_imax.as_bytes()).is_err());
        assert!(plan_recovery(0, format!("{audit_imax}x").as_bytes()).is_err());
    }

    #[test]
    fn test_s68_sin_table_sha256_parity_with_julia() {
        use crate::sin_table::*;
        let got = verify_sin_table_sha256();
        assert_eq!(got, SIN_TABLE_SHA256);
        assert_eq!(
            got,
            "170c65dfadc4e2c345cff8e1bd5a5d34f191e844a55f0c158492251febecc58a"
        );
        let tbl = sin_table_1000();
        assert_eq!(tbl[0].to_bits(), 0x0000000000000000);
        assert_eq!(tbl[250].to_bits(), 0x3ff0000000000000);
        assert_eq!(tbl[500].to_bits(), 0x3ca1a62633145c07);
        assert_eq!(tbl[750].to_bits(), 0xbff0000000000000);
        // Frozen table integrates cleanly with compute_c4_yields
        let (g1, g2) = compute_c4_yields(&tbl, 0, 999.0, 999.0, true);
        assert_eq!((g1, g2), (2.0, 3.0));
    }

    #[test]
    fn test_trm_infer_bit_exact_with_julia_and_0cycle_fallback() {
        use crate::head_c2::{HeadC2, HeadWeights, HIDDEN};
        use crate::trm_infer::*;

        let dryrun_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("experiments")
            .join("pi5_p2_dryrun")
            .join("out");
        let b_ok = dryrun_dir.join("s47_dryrun.bin");
        let b_1ulp = dryrun_dir.join("s47_dryrun_1ulp.bin");
        if !b_ok.exists() || !b_1ulp.exists() {
            return; // skip only if regenerable dryrun bundle is absent
        }

        let bytes_ok = std::fs::read(&b_ok).unwrap();
        let out_ok = run_trm_bundle(&bytes_ok).unwrap();
        assert_eq!(
            sha256_hex(&out_ok),
            "7486cd15cd1eb8f00f696c2f77cd34f06dbd198bb4c7618c1ca07c6b62963e41",
            "onelife-trm internal TRM inference must match Julia TrmDet.jl bit-for-bit!"
        );

        let bytes_1ulp = std::fs::read(&b_1ulp).unwrap();
        let out_1ulp = run_trm_bundle(&bytes_1ulp).unwrap();
        assert_eq!(
            sha256_hex(&out_1ulp),
            "812c5934eea0cf5fc0d104d9784725915cfed95b490e6885393917c0a1cb24ca"
        );

        // Verify budgeted forward pass: 0-cycle fallback returns exact H_init; 3-cycle feeds HeadC2 cleanly
        let model = TrmModel::from_bundle_bytes(&bytes_ok).unwrap();
        let toks = vec![0i32; 47];
        let o0 = model.forward_budgeted(&toks, 0).unwrap();
        assert_eq!(o0.h_cycles_completed, 0);
        assert_eq!(o0.ops_used, OPS_FIXED);
        assert_eq!(&o0.h_pos45[..], &model.hinit[..HIDDEN]);
        assert_eq!(&o0.h_pos46[..], &model.hinit[..HIDDEN]);

        let o3 = model.forward_budgeted(&toks, 3).unwrap();
        assert_eq!(o3.h_cycles_completed, 3);
        assert_eq!(o3.ops_used, OPS_FIXED + 3 * OPS_PER_H_CYCLE);
        assert_ne!(o3.h_pos45, o0.h_pos45);

        // End-to-end TRM -> HeadC2 predict -> post_step_update
        let head = HeadC2::new(
            HeadWeights {
                w8: [0.1f32; HIDDEN],
                w7: [-0.1f32; HIDDEN],
                we: [0.05f32; HIDDEN],
                be: 0.0f32,
            },
            0.03125f32,
        )
        .unwrap();
        let p1 = head.predict(&o3.h_pos45);
        let p2 = head.predict(&o3.h_pos46);
        assert!(p1.p.is_finite() && p2.p.is_finite() && p1.e.is_finite() && p2.e.is_finite());
    }
}
