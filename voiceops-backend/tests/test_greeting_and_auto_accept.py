"""
Tests for enhanced agent greeting and automatic order acceptance.
"""
import pytest
from app.agents.agent_config import (
    get_agent_greeting,
    _GREETING_SALUTATIONS,
    _GREETING_WARM_LINES,
    _GREETING_SELF_INTROS,
    _GREETING_QUESTIONS,
)


class TestEnhancedGreeting:
    """Test that the agent greeting is short, calm, and genuinely varied."""

    def test_greeting_includes_warm_line(self):
        """Test that greeting includes one of the warm lines."""
        greeting = get_agent_greeting("John", question_index=0)
        assert any(line in greeting for line in _GREETING_WARM_LINES)

    def test_greeting_is_short(self):
        """Test that the greeting is short, not the old long fixed script."""
        greeting = get_agent_greeting("Maria", question_index=0)
        assert len(greeting) < 220

    def test_greeting_drops_feature_list_and_voice_customization(self):
        """Test that the old fixed feature list and 'customize by voice' text are gone."""
        greeting = get_agent_greeting("Maria", question_index=0)
        assert "customize" not in greeting.lower()
        assert "navigate routes" not in greeting
        assert "handle customer communications" not in greeting

    def test_greeting_includes_context(self):
        """Test that greeting provides helpful context."""
        greeting = get_agent_greeting("Driver", question_index=0)
        assert "Kora" in greeting
        assert "co-rider" in greeting

    def test_greeting_varies_by_question_index(self):
        """Test that greeting variations work with question index."""
        greeting1 = get_agent_greeting("Test", question_index=0)
        greeting2 = get_agent_greeting("Test", question_index=1)
        assert greeting1 != greeting2

    def test_greeting_pools_exist_and_are_distinct(self):
        """Test that all the variation pools are populated with distinct entries."""
        assert len(_GREETING_SALUTATIONS) > 1
        assert len(_GREETING_WARM_LINES) > 1
        assert len(_GREETING_SELF_INTROS) > 1
        assert len(_GREETING_QUESTIONS) > 1

    def test_greeting_handles_empty_name(self):
        """Test greeting handles empty or None driver name with a graceful no-name salutation."""
        greeting = get_agent_greeting("", question_index=0)
        assert any(no_name in greeting for _, no_name in _GREETING_SALUTATIONS)

    def test_greeting_handles_driver_placeholder(self):
        """Test greeting handles 'Driver' placeholder with a graceful no-name salutation."""
        greeting = get_agent_greeting("Driver", question_index=0)
        assert any(no_name in greeting for _, no_name in _GREETING_SALUTATIONS)

    def test_greeting_uses_name_when_known(self):
        """Test greeting weaves the driver's real name into the salutation."""
        greeting = get_agent_greeting("Sam", question_index=2)
        assert "Sam" in greeting

    def test_many_random_draws_produce_several_different_greetings(self):
        """Test that unset question_index yields genuine variety, not one fixed response."""
        greetings = {get_agent_greeting("Sam") for _ in range(40)}
        assert len(greetings) > 5


class TestAutoAcceptIntegration:
    """Test automatic order acceptance integration."""
    
    def test_auto_accept_method_exists(self):
        """Test that auto-accept method exists in dispatcher."""
        from app.dispatch.order_dispatch import OrderDispatcher
        dispatcher = OrderDispatcher.__new__(OrderDispatcher)
        assert hasattr(dispatcher, '_maybe_auto_accept')
    
    def test_incoming_order_has_enhanced_fields(self):
        """Test that IncomingOrder has new fields for enhanced preferences."""
        from app.integrations.logistics.base import IncomingOrder
        # Check that the class has the new fields
        import inspect
        fields = [f.name for f in inspect.signature(IncomingOrder).parameters.values()]
        assert 'category' in fields
        assert 'weight_kg' in fields
        assert 'dimensions' in fields
        assert 'value' in fields
    
    def test_order_details_schema_has_enhanced_fields(self):
        """Test that OrderDetails schema has enhanced fields."""
        from app.models.schemas import OrderDetails
        # Check that the schema has the new fields
        import inspect
        fields = [f.name for f in inspect.signature(OrderDetails).parameters.values()]
        assert 'category' in fields
        assert 'weight_kg' in fields
        assert 'dimensions' in fields
        assert 'value' in fields
    
    def test_agent_config_mentions_auto_accept(self):
        """Test that agent config explains auto-accept feature."""
        from app.agents.agent_config import get_system_prompt
        prompt = get_system_prompt()
        assert "auto_accept" in prompt.lower()
        assert "automatically" in prompt.lower()
    
    def test_greeting_preserves_functionality(self):
        """Test that greeting still introduces Kora as the co-rider and asks a question."""
        greeting = get_agent_greeting("TestDriver", question_index=0)
        assert "Kora" in greeting
        assert "co-rider" in greeting
        assert greeting.rstrip().endswith("?")