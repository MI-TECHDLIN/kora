"""
Tests for enhanced agent greeting and automatic order acceptance.
"""
import pytest
from app.agents.agent_config import get_agent_greeting, _CALM_OPENINGS, _GREETING_QUESTIONS


class TestEnhancedGreeting:
    """Test enhanced agent greeting with calm openings."""
    
    def test_greeting_includes_calm_opening(self):
        """Test that greeting includes a calm opening."""
        greeting = get_agent_greeting("John", question_index=0)
        assert "Good to see you on the road today" in greeting or "Hope you're having a smooth start" in greeting
    
    def test_greeting_is_more_natural(self):
        """Test that greeting feels more natural and less transactional."""
        greeting = get_agent_greeting("Maria")
        # Should not immediately jump to customization
        assert "Hello, Maria" in greeting
        # Should include calm opening before customization info
        assert greeting.find("Hello") < greeting.find("customize")
    
    def test_greeting_includes_context(self):
        """Test that greeting provides helpful context."""
        greeting = get_agent_greeting("Driver")
        assert "Kora" in greeting
        assert "co-rider" in greeting
        assert "deliveries" in greeting or "help" in greeting
    
    def test_greeting_varies_by_question_index(self):
        """Test that greeting variations work with question index."""
        greeting1 = get_agent_greeting("Test", question_index=0)
        greeting2 = get_agent_greeting("Test", question_index=1)
        # Should have different questions
        assert greeting1 != greeting2
    
    def test_greeting_calm_openings_exist(self):
        """Test that calm openings are defined."""
        assert len(_CALM_OPENINGS) > 0
        assert len(_GREETING_QUESTIONS) > 0
    
    def test_greeting_handles_empty_name(self):
        """Test greeting handles empty or None driver name."""
        greeting = get_agent_greeting("")
        assert "Hello there" in greeting
    
    def test_greeting_handles_driver_placeholder(self):
        """Test greeting handles 'Driver' placeholder."""
        greeting = get_agent_greeting("Driver")
        assert "Hello there" in greeting


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
        """Test that enhanced greeting still preserves all original functionality."""
        greeting = get_agent_greeting("TestDriver")
        # Should still include essential elements
        assert "Kora" in greeting
        assert "co-rider" in greeting
        assert "customize" in greeting.lower()
        assert "How has your day been" in greeting