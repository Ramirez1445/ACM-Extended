from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8-sig", errors="strict")


def test_obsolete_acm_syringes_self_menu_is_removed():
    core = read("addons/core/CfgVehicles.hpp")
    assert "class ACM_Action_Syringe" not in core
    assert "ECSTRING(circulation,Syringes)" not in core
    assert "Syringe_ChildActions" not in core


def test_obsolete_push_dose_self_menu_is_removed():
    cfg = read("addons/acm_extended/config.cpp")
    assert "class ACME_FlushMenu" not in cfg
    assert 'displayName = "Saline Flush / Push-Dose Epi"' not in cfg
    assert "class ACME_Flush_Prep" not in cfg
    assert "class ACME_Flush_DrawDirtyPrep" not in cfg


def test_supported_medication_self_menus_remain():
    cfg = read("addons/acm_extended/config.cpp")
    assert "class ACME_SyringeKit" in cfg
    assert 'displayName = "Narc Box"' in cfg
    assert "class ACME_DrawnSyringes" in cfg
    assert 'displayName = "Drawn Syringes"' in cfg
