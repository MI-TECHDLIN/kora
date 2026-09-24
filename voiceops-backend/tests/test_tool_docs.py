"""
Keep the tool documentation in step with the registry.

`app/agents/tool_registry.py` (`TOOL_EXECUTORS`) is the source of truth for which tools exist.
`docs/VoiceOps_Agent_Tools_Reference.md` and the tool table in the repo's `AGENTS.md` must each
list every registered tool, and the reference's "The N Tools" heading must state the real count.
Adding a tool without updating the docs fails these tests.
"""
import re
from pathlib import Path

import pytest

from app.agents.tool_registry import TOOL_EXECUTORS, get_tools

REPO_ROOT = Path(__file__).resolve().parents[2]
REFERENCE = REPO_ROOT / "docs" / "VoiceOps_Agent_Tools_Reference.md"
AGENTS_MD = REPO_ROOT / "AGENTS.md"

pytestmark = pytest.mark.skipif(
    not REFERENCE.exists() or not AGENTS_MD.exists(),
    reason="monorepo docs not present next to voiceops-backend/",
)


def test_registry_schemas_and_executors_agree():
    assert {t["name"] for t in get_tools()} == set(TOOL_EXECUTORS)


def test_reference_documents_exactly_the_registered_tools():
    text = REFERENCE.read_text(encoding="utf-8")
    documented = re.findall(r"^### [\d.]+ `([a-z_]+)`", text, flags=re.MULTILINE)

    assert len(documented) == len(set(documented)), "a tool is documented twice in the reference"
    assert set(documented) == set(TOOL_EXECUTORS), (
        f"reference is missing {sorted(set(TOOL_EXECUTORS) - set(documented))}, "
        f"documents unregistered {sorted(set(documented) - set(TOOL_EXECUTORS))}"
    )


def test_reference_heading_states_the_registry_count():
    text = REFERENCE.read_text(encoding="utf-8")
    heading = re.search(r"^## The (\d+) Tools$", text, flags=re.MULTILINE)
    assert heading, "reference needs a '## The N Tools' heading"
    assert int(heading.group(1)) == len(TOOL_EXECUTORS)

    intro = re.search(r"contract\*\* for the (\d+) agent tools", text)
    assert intro, "reference intro must state the tool count"
    assert int(intro.group(1)) == len(TOOL_EXECUTORS)


def test_agents_md_table_lists_exactly_the_registered_tools():
    text = AGENTS_MD.read_text(encoding="utf-8")
    section = re.search(r"^## The Agent Tools$(.*?)^## ", text, flags=re.MULTILINE | re.DOTALL)
    assert section, "AGENTS.md needs a '## The Agent Tools' section"
    listed = re.findall(r"^\| `([a-z_]+)` \|", section.group(1), flags=re.MULTILINE)
    assert set(listed) == set(TOOL_EXECUTORS), (
        f"AGENTS.md tool table is missing {sorted(set(TOOL_EXECUTORS) - set(listed))}, "
        f"lists unregistered {sorted(set(listed) - set(TOOL_EXECUTORS))}"
    )
