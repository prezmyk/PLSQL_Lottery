
-- Create GUEST_USER
-- DROP USER guest_user CASCADE;
CREATE USER guest_user IDENTIFIED BY ...;
GRANT CONNECT TO guest_user;
GRANT SELECT ON v_recent_winning_numbers TO guest_user;
GRANT SELECT ON v_recent_winners_with_amount TO guest_user;
GRANT SELECT ON v_recent_rollovers TO guest_user;
GRANT EXECUTE ON guest_pkg TO guest_user;

-- synonyms
CREATE SYNONYM guest_user.winning_numbers 
	FOR v_recent_winning_numbers;
CREATE SYNONYM guest_user.winners_with_amount 
	FOR v_recent_winners_with_amount;
CREATE SYNONYM guest_user.rollovers 
	FOR v_recent_rollovers;
CREATE SYNONYM guest_user.guest_pkg 
	FOR guest_pkg;	


-- Limits
BEGIN
    -- 1. Reset pending area to clear any previous uncommitted changes
    CS_RESOURCE_MANAGER.CLEAR_PENDING_AREA;
    CS_RESOURCE_MANAGER.CREATE_PENDING_AREA;

    -- 2. Remove existing configuration if present to allow repeated script execution
    BEGIN
        CS_RESOURCE_MANAGER.DELETE_PLAN(plan => 'GUEST_LIMITS_PLAN', cascade => TRUE);
    EXCEPTION WHEN OTHERS THEN NULL; -- Ignore error if plan does not exist yet
    END;

    BEGIN
        CS_RESOURCE_MANAGER.DELETE_CONSUMER_GROUP(consumer_group => 'GUEST_GROUP');
    EXCEPTION WHEN OTHERS THEN NULL; -- Ignore error if group does not exist yet
    END;

    -- 3. Create consumer group for guest sessions
    CS_RESOURCE_MANAGER.CREATE_CONSUMER_GROUP(
        consumer_group => 'GUEST_GROUP',
        comment        => 'Limited resources for guest access'
    );

    -- 4. Create resource plan
    CS_RESOURCE_MANAGER.CREATE_PLAN(
        plan    => 'GUEST_LIMITS_PLAN',
        comment => 'Dedicated resource limit plan for guest sessions'
    );

    -- 5. Plan directive for guest group
    CS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
        plan                          => 'GUEST_LIMITS_PLAN',
        consumer_group                => 'GUEST_GROUP',
        comment                       => 'Resource restrictions for guest sessions',
        shares                        => 1,
        active_session_limit          => 1,
        parallel_queue_timeout        => 3,
        parallel_queue_timeout_action => 'CANCEL',
        elapsed_time_limit            => 2,
        switch_action                 => 'LOW'
    );

    -- 6. Mandatory directive for all other database users
    CS_RESOURCE_MANAGER.CREATE_PLAN_DIRECTIVE(
        plan                          => 'GUEST_LIMITS_PLAN',
        consumer_group                => 'OTHER_GROUPS',
        comment                       => 'Resources for all remaining database users',
        shares                        => 5
    );

    -- 7. Map guest user to consumer group
    CS_RESOURCE_MANAGER.SET_CONSUMER_GROUP_MAPPING(
        attribute      => 'ORACLE_USER',
        value          => 'GUEST_USER',
        consumer_group => 'GUEST_GROUP'
    );

    -- 8. Submit and activate pending changes
    CS_RESOURCE_MANAGER.SUBMIT_PENDING_AREA;
END;
/








