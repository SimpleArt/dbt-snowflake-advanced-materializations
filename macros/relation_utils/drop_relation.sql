{% macro drop_relation(relation, drop_unless_type=none, metadata=none, transient=none) %}

    {% set result = get_relation_type(relation) %}
    {% set type = result.get('type') %}
    {% set row = result.get('row') %}

    {% if drop_unless_type is none %}
        {% set drop_unless_type = relation.type %}
    {% endif %}

    {% if type is none or not execute %}
        {# If the object doesn't already exist, run create or replace, #}
        {# which may include additional parameters, such as "create or replace secure ...", #}
        {# which ensures additional "alter" queries do not need to be ran. #}
        {{ return('create or replace') }}

    {% elif type in ['function', 'procedure'] %}
        {% if type == 'function' %}
            {% set show_type = 'user function' %}
        {% else %}
            {% set show_type = 'procedure' %}
        {% endif %}

        {% set results = run_query(show_relation(relation, show_type)) %}

        {# If a function/procedure needs to be created, first check if it's already created. #}
        {% if type == drop_unless_type %}
            {% for row in results if row['name'] == relation.identifier %}
                {% set comment = row.get('comment', row.get('description', '')) %}
                {% set state = {'flag': false} %}

                {% for part in metadata if part in comment %}
                    {% do state.update({'flag': true}) %}
                {% endfor %}

                {% if state['flag'] %}
                    {{ return('create if not exists') }}
                {% endif %}
            {% endfor %}

        {# If no matching function/procedure is found, drop all functions/procedures. #}
        {% else %}
            {% for row in results if row['name'] == relation.identifier %}
                {% call statement('drop_callable') %}
                    drop {{ type }} if exists {{ relation }}({{ row['arguments'][(relation.identifier|length + 1):].split(') RETURN ')[0] }})
                {% endcall %}
            {% endfor %}

        {% endif %}

        {{ return('create or replace') }}

    {% elif type != drop_unless_type %}
        {# If the object exists of the wrong type, then drop it. #}
        {% call statement('drop_object') %}
            drop {{ type }} if exists {{ relation }}
        {% endcall %}

        {{ return('create or replace') }}

    {% endif %}

    {# If the object is a stream, a "show streams" query was already ran. #}
    {% if type == 'stream' and row is not none %}
        {% set comment = row.get('comment', row.get('description')) %}

        {% if row.get('stale') == 'true' %}
            {{ return('create or replace') }}

        {% elif metadata is not none %}
            {% for part in metadata if part not in comment %}
                {{ return('create or replace') }}
            {% endfor %}

        {% endif %}

    {# Check if the existing object matches the expected object. #}
    {% elif metadata is not none or transient is not none %}
        {% for row in run_query(show_relation(relation, type)) %}
            {% set text = row.get('text') %}
            {% set comment = row.get('comment', row.get('description')) %}
            {% set scheduling_state = row.get('scheduling_state') %}

            {% if scheduling_state == 'SUSPENDED' %}
                {{ return('create or replace') }}
            {% elif transient is not none %}
                {% if transient and row.get('kind') != 'TRANSIENT' %}
                    {{ return('create or replace') }}
                {% elif not transient and row.get('kind') == 'TRANSIENT' %}
                    {{ return('create or replace') }}
                {% endif %}
            {% endif %}

            {% if metadata is not none %}
                {% for part in metadata if part not in text and part not in comment %}
                    {{ return('create or replace') }}
                {% endfor %}
            {% endif %}
        {% endfor %}
    {% endif %}

    {# Check if the existing object can still be queried. #}
    {% if is_queryable(relation) %}
        {{ return('create if not exists') }}
    {% else %}
        {{ return('create or replace') }}
    {% endif %}

{% endmacro %}
