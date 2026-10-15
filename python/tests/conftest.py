import pandas as pd
import pytest

from shotorpass.features import build_shots
from shotorpass.statsbomb import ROOT, sb_matches, sb_path

R_REFERENCE = ROOT / "cache" / "r-reference"


@pytest.fixture(scope="session")
def r_ref():
    """Reader for the tables export_r_reference.R wrote."""
    if not R_REFERENCE.exists():
        pytest.skip("no R reference: run `Rscript python/tests/export_r_reference.R` "
                    "from the repository root first")

    # round_trip because pandas' default float parser can land one bit off the
    # value R wrote at 17 significant digits
    def read(name):
        return pd.read_csv(R_REFERENCE / name, float_precision="round_trip")
    return read


@pytest.fixture(scope="session")
def shots_all():
    """The shot table built fresh from the raw files, never from a cache."""
    if not sb_path("matches.json").exists():
        pytest.skip("no raw StatsBomb data in data-raw/")
    return build_shots([m["match_id"] for m in sb_matches()], verbose=False)


@pytest.fixture(scope="session")
def shots(shots_all):
    return shots_all[shots_all["shot_type"] != "Free Kick"].reset_index(drop=True)
