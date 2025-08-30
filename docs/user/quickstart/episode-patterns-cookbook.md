# Episode Patterns Cookbook

## Why This Matters
Copy-paste ready patterns for common Graphiti use cases. Each pattern is optimized for entity extraction, relationship discovery, and temporal reasoning.

## The Episode Approach
Episodes are your only interface to Graphiti. These patterns show exactly how to structure episodes for maximum effectiveness.

## Customer Conversation Patterns

### Customer Support Interaction
```python
# Pattern: Multi-turn support conversation
await graphiti.add_episode(
    name=f"support_ticket_{ticket_id}",
    episode_body=f"""
    Customer: {customer_name} (ID: {customer_id})
    Issue: {issue_description}
    
    Agent: {agent_name} (ID: {agent_id})
    Response: {agent_response}
    
    Resolution: {resolution_status}
    Satisfaction: {satisfaction_score}/5
    """,
    source=EpisodeType.message,
    source_description=f"Support ticket #{ticket_id}",
    reference_time=datetime.now(timezone.utc)
)
```

### Customer Preference Update
```python
# Pattern: Preference changes over time
await graphiti.add_episode(
    name=f"preference_update_{customer_id}_{timestamp}",
    episode_body=f"{customer_name} now prefers {new_preference} instead of {old_preference} because {reason}",
    source=EpisodeType.text,
    source_description="Preference tracking system",
    reference_time=datetime.now(timezone.utc)
)
```

### Purchase History
```python
# Pattern: Transaction with context
await graphiti.add_episode(
    name=f"purchase_{order_id}",
    episode_body={
        "customer": {"id": customer_id, "name": customer_name},
        "items": [
            {"product": product_name, "quantity": qty, "price": price}
            for product_name, qty, price in items
        ],
        "total": total_amount,
        "payment_method": payment_method,
        "shipping_address": address
    },
    source=EpisodeType.json,
    source_description="E-commerce transaction",
    reference_time=purchase_timestamp
)
```

## Product Catalog Patterns

### Product Information Update
```python
# Pattern: Structured product data
await graphiti.add_episode(
    name=f"product_update_{product_id}_{timestamp}",
    episode_body={
        "product_id": product_id,
        "name": product_name,
        "category": category,
        "price": {"amount": price, "currency": "USD"},
        "inventory": {"in_stock": quantity, "warehouse": location},
        "attributes": {
            "color": colors,
            "size": sizes,
            "material": materials
        },
        "related_products": related_ids
    },
    source=EpisodeType.json,
    source_description="Product catalog sync",
    reference_time=datetime.now(timezone.utc)
)
```

### Inventory Alert
```python
# Pattern: Time-sensitive update
await graphiti.add_episode(
    name=f"inventory_alert_{product_id}",
    episode_body=f"URGENT: {product_name} is {status}. Current stock: {quantity}. Reorder point: {reorder_point}. Next shipment: {shipment_date}",
    source=EpisodeType.text,
    source_description="Inventory management system",
    reference_time=datetime.now(timezone.utc)
)
```

### Product Review
```python
# Pattern: Customer feedback with sentiment
await graphiti.add_episode(
    name=f"review_{review_id}",
    episode_body=f"""
    Product: {product_name}
    Customer: {customer_name}
    Rating: {rating}/5
    Review: "{review_text}"
    Verified Purchase: {is_verified}
    Helpful Votes: {helpful_count}
    """,
    source=EpisodeType.text,
    source_description="Product review system",
    reference_time=review_date
)
```

## Team Knowledge Patterns

### Meeting Notes
```python
# Pattern: Multi-participant discussion
await graphiti.add_episode(
    name=f"meeting_{meeting_id}",
    episode_body={
        "meeting": {
            "title": meeting_title,
            "date": meeting_date,
            "attendees": [
                {"name": name, "role": role} 
                for name, role in attendees
            ]
        },
        "discussions": [
            {"topic": topic, "speaker": speaker, "decision": decision}
            for topic, speaker, decision in discussions
        ],
        "action_items": [
            {"task": task, "assignee": assignee, "due_date": due}
            for task, assignee, due in action_items
        ]
    },
    source=EpisodeType.json,
    source_description="Meeting transcript",
    reference_time=meeting_date
)
```

### Project Status Update
```python
# Pattern: Temporal project tracking
await graphiti.add_episode(
    name=f"project_status_{project_id}_{week}",
    episode_body=f"""
    Project: {project_name}
    Week: {week_number}
    Status: {status_color}
    
    Completed:
    {completed_items}
    
    In Progress:
    {in_progress_items}
    
    Blockers:
    {blockers}
    
    Next Week:
    {next_week_plan}
    """,
    source=EpisodeType.text,
    source_description="Weekly status report",
    reference_time=report_date
)
```

## Event and Monitoring Patterns

### System Event
```python
# Pattern: Technical event with context
await graphiti.add_episode(
    name=f"system_event_{event_id}",
    episode_body={
        "event_type": event_type,
        "severity": severity_level,
        "component": affected_component,
        "message": error_message,
        "stack_trace": stack_trace if severity == "ERROR" else None,
        "metrics": {
            "cpu": cpu_usage,
            "memory": memory_usage,
            "requests_per_second": rps
        },
        "affected_users": affected_user_count
    },
    source=EpisodeType.json,
    source_description="System monitoring",
    reference_time=event_timestamp
)
```

### User Activity
```python
# Pattern: User behavior tracking
await graphiti.add_episode(
    name=f"user_activity_{user_id}_{session_id}",
    episode_body=f"""
    User {user_name} performed the following actions:
    1. Viewed {pages_viewed} pages
    2. Clicked on {clicks} items
    3. Spent {time_spent} minutes on site
    4. Converted: {did_convert}
    Cart Value: ${cart_value}
    """,
    source=EpisodeType.text,
    source_description="Analytics tracking",
    reference_time=session_end_time
)
```

## Temporal Patterns

### Fact Invalidation
```python
# Pattern: Explicitly supersede old information
# Monday - Original fact
await graphiti.add_episode(
    name="price_update_001",
    episode_body="Product ABC costs $99",
    source=EpisodeType.text,
    reference_time=monday_date
)

# Wednesday - Supersedes Monday's price
await graphiti.add_episode(
    name="price_update_002",
    episode_body="Product ABC now costs $79 (was $99)",
    source=EpisodeType.text,
    reference_time=wednesday_date  # Later timestamp invalidates earlier
)
```

### Time-Range Query Pattern
```python
# Pattern: Events within time window
async def get_recent_activities(user_name: str, days_back: int = 7):
    query = f"all activities by {user_name} in the last {days_back} days"
    results = await graphiti.search(
        query,
        num_results=50
    )
    return results
```

## Observability

Each pattern automatically generates Langfuse traces:

```
Episode Pattern Trace:
┌─ add_episode(customer_support) ───────────────────┐
│ Pattern: Multi-turn conversation                   │
│                                                    │
│ Entities Extracted:                               │
│ - Customer(name="John", id="C123")                │
│ - Agent(name="Sarah", id="A456")                  │
│ - Issue(type="return", status="resolved")         │
│                                                    │
│ Relationships Created:                            │
│ - Customer REPORTED Issue                         │
│ - Agent RESOLVED Issue                            │
│ - Customer SATISFIED_WITH Agent (score=5)         │
│                                                    │
│ Processing: 823ms, $0.0018                        │
└───────────────────────────────────────────────────┘
```

## Performance Impact

Pattern efficiency comparison:

| Pattern | Processing Time | Entities/Episode | Use When |
|---------|----------------|------------------|----------|
| JSON structured | 200-500ms | 5-20 | Known schema |
| Text narrative | 500-1500ms | 2-8 | Natural language |
| Message conversation | 800-2000ms | 3-12 | Multi-turn dialogue |

## Common Issues

### Over-Structuring Text Episodes
```python
# ❌ Wrong: Too structured for text type
await graphiti.add_episode(
    episode_body="key1:value1,key2:value2,key3:value3",  # Looks like JSON
    source=EpisodeType.text  # But processed as text
)

# ✅ Right: Use JSON for structured data
await graphiti.add_episode(
    episode_body={"key1": "value1", "key2": "value2"},
    source=EpisodeType.json
)
```

### Missing Temporal Context
```python
# ❌ Wrong: No time reference
await graphiti.add_episode(
    episode_body="Price changed to $99",
    reference_time=None  # When did this happen?
)

# ✅ Right: Always include time
await graphiti.add_episode(
    episode_body="Price changed to $99",
    reference_time=datetime.now(timezone.utc)
)
```

### Batch Size Problems
```python
# ❌ Wrong: Huge batch causes OOM
episodes = load_10000_episodes()
for ep in episodes:
    await graphiti.add_episode(ep)  # Memory explosion

# ✅ Right: Controlled batching
async def batch_ingest(episodes, batch_size=10):
    for i in range(0, len(episodes), batch_size):
        batch = episodes[i:i+batch_size]
        for ep in batch:
            await graphiti.add_episode(ep)
        await asyncio.sleep(0.1)  # Allow memory recovery
```

## Next Steps
- [Customer Support System](../examples/customer-support-system/01-setup.md) - Full implementation
- [Episode Types Deep Dive](../../dev/episodes/episode-types-deep-dive.md) - When to use each type
- [Search Configurations](../../dev/episodes/search-configurations.md) - Retrieving your episodes
- [Temporal Patterns](../../dev/episodes/temporal-invalidation-patterns.md) - Advanced time handling