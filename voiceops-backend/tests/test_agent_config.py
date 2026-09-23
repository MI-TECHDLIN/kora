from app.agents.agent_config import get_agent_greeting, get_system_prompt


def test_first_greeting_is_personal_polite_and_lively():
    greeting = get_agent_greeting("Ada", question_index=0)

    assert greeting.startswith("Hello, Ada!")
    assert "I'm Kora, your co-rider" in greeting
    assert "How has your day been so far?" in greeting
    assert "one good thing" in greeting


def test_first_greeting_question_can_vary_deterministically():
    first = get_agent_greeting("Ada", question_index=0)
    second = get_agent_greeting("Ada", question_index=1)

    assert first != second
    assert "looking forward to after your shift" in second


def test_every_reply_is_instructed_to_be_calm_and_friendly():
    prompt = get_system_prompt("Ada")

    assert "calm, warm, and friendly manner in every response" in prompt
    assert "reassuring and respectful" in prompt
