	--------------------------------------------------
	-- PROGRAMS
	--------------------------------------------------
BEGIN
	DBMS_SCHEDULER.create_program (
		program_name        => 'prg_generate_random_coupon',
		program_type        => 'PLSQL_BLOCK',
		program_action      => q'[
	BEGIN
		FOR i IN 1..1000
		LOOP
			 lotto_pkg.generate_random_coupon(p_game_id => lotto_pkg.c_big_lotto);
			 lotto_pkg.generate_random_coupon(p_game_id => lotto_pkg.c_express_lotto);
		END LOOP;
		COMMIT;
	END;    
	]',
		enabled => TRUE,  
		comments => 'Generates random coupons for both lottery games to simulate user activity'
	);

	DBMS_SCHEDULER.create_program (
		program_name        => 'prg_draw_numbers',
		program_type        => 'PLSQL_BLOCK',
		program_action      => q'[
	BEGIN
		lotto_pkg.draw_numbers(p_game_id => lotto_pkg.c_big_lotto);
		lotto_pkg.draw_numbers(p_game_id => lotto_pkg.c_express_lotto);
		COMMIT;
	END;    
	]',
		enabled => TRUE,  
		comments => 'Performs daily draw for all configured lottery games'
	);

	DBMS_SCHEDULER.create_program (
		program_name        => 'prg_check_winners',
		program_type        => 'PLSQL_BLOCK',
		program_action      => q'[
	BEGIN	
		lotto_pkg.calculate_winners(p_game_id => lotto_pkg.c_big_lotto);
		lotto_pkg.calculate_winners(p_game_id => lotto_pkg.c_express_lotto);
		COMMIT;
	END;    
	]',
		enabled => TRUE,  
		comments => 'Calculates winners, payouts and jackpot rollover after daily draw'
	);
	
	DBMS_SCHEDULER.create_program (
		program_name        => 'prg_create_mon_arch',
		program_type        => 'PLSQL_BLOCK',
		program_action      => q'[
	BEGIN	
		lotto_pkg.create_mon_arch;
	END;    
	]',
		enabled => TRUE,  
		comments => 'Archives monthly winner statistics from operational tables'
	);
	
	DBMS_SCHEDULER.create_program (
		program_name        => 'prg_create_halfyear_archive',
		program_type        => 'PLSQL_BLOCK',
		program_action      => q'[
	BEGIN	
		lotto_pkg.create_halfyear_archive;
	END;    
	]',
		enabled => TRUE,  
		comments => 'Aggregates monthly archives into long-term historical archive'
	);
	
	DBMS_SCHEDULER.create_program (
		program_name        => 'prg_clean_halfyear_archive',
		program_type        => 'PLSQL_BLOCK',
		program_action      => q'[
	BEGIN	
		DELETE FROM winners_monthly_archive;
		COMMIT;
	END;    
	]',
		enabled => TRUE,  
		comments => 'Removes monthly archives'
	);
	
	DBMS_SCHEDULER.create_program (
		program_name        => 'prg_clean_mon_data',
		program_type        => 'PLSQL_BLOCK',
		program_action      => q'[
	BEGIN	
		lotto_pkg.clean_mon_data;
		COMMIT;
	END;    
	]',
		enabled => TRUE,  
		comments => 'Removes operational data after successful archive while retaining top winners history'
	);
	
	
END;
/

	--------------------------------------------------
	-- SCHEDULES
	--------------------------------------------------

BEGIN
	DBMS_SCHEDULER.CREATE_SCHEDULE (
		schedule_name  => 'sch_generate_random_coupon',
		repeat_interval  => 'FREQ=HOURLY; INTERVAL=8',     
		start_date => FROM_TZ(CAST(TRUNC(SYSDATE) + 16/24 AS TIMESTAMP),'Europe/Warsaw'),
		comments => 'Runs every 8 hours to generate sample coupon activity'
	);

	DBMS_SCHEDULER.CREATE_SCHEDULE (
		schedule_name  => 'sch_daily_lotto_chain',
		repeat_interval  => 'FREQ=DAILY; BYHOUR=19; BYMINUTE=0; BYSECOND=0',     
		start_date => FROM_TZ(CAST(TRUNC(SYSDATE) + 19/24 AS TIMESTAMP),'Europe/Warsaw'),
		comments => 'Runs daily at 19:00 Europe/Warsaw for lottery workflow'
	);
-- always archive previous full month independent of manual execution date
	DBMS_SCHEDULER.CREATE_SCHEDULE (
		schedule_name  => 'sch_monthly_arch_chain',
		repeat_interval  => 'FREQ=MONTHLY; INTERVAL=1; BYMONTHDAY=1; BYHOUR=20; BYMINUTE=0; BYSECOND=0',     
		start_date => FROM_TZ(CAST(TRUNC(SYSDATE) + 20/24 AS TIMESTAMP),'Europe/Warsaw'),
		comments => 'Runs monthly at 20:00 Europe/Warsaw for archive workflow'
	);


	DBMS_SCHEDULER.CREATE_SCHEDULE (
		schedule_name  => 'sch_halfyear_archive_chain',
		repeat_interval  => 'FREQ=YEARLY; BYMONTH=6,12; BYMONTHDAY=1; BYHOUR=22; BYMINUTE=0; BYSECOND=0',     
		start_date => FROM_TZ(CAST(TRUNC(SYSDATE) + 22/24 AS TIMESTAMP),'Europe/Warsaw'),
		comments => 'Runs half year at 22:00 Europe/Warsaw for archive workflow'
	);
	
END;
/

	--------------------------------------------------
	-- CHAINS/STEPS/RULES
	--------------------------------------------------
	--Process lotto logic
BEGIN
    DBMS_SCHEDULER.CREATE_CHAIN (
        chain_name => 'chain_daily_lotto',
        comments   => 'Executes lottery draw and winner calculation workflow'
    );


    DBMS_SCHEDULER.DEFINE_CHAIN_STEP (
        chain_name   => 'chain_daily_lotto',
        step_name    => 'step_draw_numbers',
		program_name => 'prg_draw_numbers'
    );

    DBMS_SCHEDULER.DEFINE_CHAIN_STEP (
        chain_name   => 'chain_daily_lotto',
        step_name    => 'step_check_winners',
        program_name => 'prg_check_winners'
    );


    DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
        chain_name => 'chain_daily_lotto',
        condition  => 'TRUE',
        action     => 'START step_draw_numbers',
        rule_name  => 'rule_start_draw'
    );

    DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
        chain_name => 'chain_daily_lotto',
        condition  => 'step_draw_numbers SUCCEEDED',
        action     => 'START step_check_winners',
        rule_name  => 'rule_start_winners'
    );

    DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
        chain_name => 'chain_daily_lotto',
        condition  => 'step_check_winners SUCCEEDED',
        action     => 'END',
        rule_name  => 'rule_end_daily_lotto_chain'
    );
	
	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_daily_lotto',
		condition  => 'step_draw_numbers FAILED OR step_check_winners FAILED',
		action     => 'END',
		rule_name  => 'rule_daily_lotto_error'
	);

    DBMS_SCHEDULER.ENABLE('chain_daily_lotto');
	
END;
/
-- Monthly Archive
BEGIN
	DBMS_SCHEDULER.CREATE_CHAIN (
		chain_name => 'chain_monthly_archive',
		comments   => 'Executes monthly maintenance workflow: archive winners and clean operational data'
	);


	DBMS_SCHEDULER.DEFINE_CHAIN_STEP (
		chain_name   => 'chain_monthly_archive',
		step_name    => 'step_monthly_archive',
		program_name => 'prg_create_mon_arch'
	);

	DBMS_SCHEDULER.DEFINE_CHAIN_STEP (
		chain_name   => 'chain_monthly_archive',
		step_name    => 'step_monthly_clean',
		program_name => 'prg_clean_mon_data'
	);


	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_monthly_archive',
		condition  => 'TRUE',
		action     => 'START step_monthly_archive',
		rule_name  => 'rule_monthly_archive'
	);

	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_monthly_archive',
		condition  => 'step_monthly_archive SUCCEEDED',
		action     => 'START step_monthly_clean',
		rule_name  => 'rule_monthly_clean'
	);

	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_monthly_archive',
		condition  => 'step_monthly_clean SUCCEEDED',
		action     => 'END',
		rule_name  => 'rule_end_monthly_archive_chain'
	);
	
	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_monthly_archive',
		condition  => 'step_monthly_archive FAILED OR step_monthly_clean FAILED',
		action     => 'END',
		rule_name  => 'rule_monthly_archive_error'
	);


	DBMS_SCHEDULER.ENABLE('chain_monthly_archive');
	
END;
/
	--Half-year archive
BEGIN
	DBMS_SCHEDULER.CREATE_CHAIN (
		chain_name => 'chain_halfyear_archive',
		comments   => 'Executes long-term archive aggregation and database cleanup workflow'
	);


	DBMS_SCHEDULER.DEFINE_CHAIN_STEP (
		chain_name   => 'chain_halfyear_archive',
		step_name    => 'step_halfyear_archive',
		program_name => 'prg_create_halfyear_archive'
	);

	DBMS_SCHEDULER.DEFINE_CHAIN_STEP (
		chain_name   => 'chain_halfyear_archive',
		step_name    => 'step_halfyear_clean',
		program_name => 'prg_clean_halfyear_archive'
	);


	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_halfyear_archive',
		condition  => 'TRUE',
		action     => 'START step_halfyear_archive',
		rule_name  => 'rule_halfyear_archive'
	);

	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_halfyear_archive',
		condition  => 'step_halfyear_archive SUCCEEDED',
		action     => 'START step_halfyear_clean',
		rule_name  => 'rule_halfyear_clean'
	);

	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_halfyear_archive',
		condition  => 'step_halfyear_clean SUCCEEDED',
		action     => 'END',
		rule_name  => 'rule_end_halfyear_archive_chain'
	);
	
	DBMS_SCHEDULER.DEFINE_CHAIN_RULE (
		chain_name => 'chain_halfyear_archive',
		condition  => 'step_halfyear_archive FAILED OR step_halfyear_clean FAILED',
		action     => 'END',
		rule_name  => 'rule_halfyear_archive_error'
	);

	DBMS_SCHEDULER.ENABLE('chain_halfyear_archive');
	
END;
/	
	
	
	--------------------------------------------------
	-- JOBS
	--------------------------------------------------
BEGIN
	DBMS_SCHEDULER.create_job (
		job_name        => 'job_generate_random_coupon',
		program_name    => 'prg_generate_random_coupon',
		schedule_name   => 'sch_generate_random_coupon',
		enabled         => TRUE,
		comments        => 'Job binding coupon generation program with schedule'
	);

	DBMS_SCHEDULER.CREATE_JOB (
		job_name        => 'job_daily_lotto_chain',
		job_type        => 'CHAIN',
		job_action      => 'chain_daily_lotto',
		schedule_name   => 'sch_daily_lotto_chain',
		enabled         => TRUE,
		comments        => 'Runs daily lottery workflow chain'
	);
	
	DBMS_SCHEDULER.CREATE_JOB (
		job_name        => 'job_monthly_archive_chain',
		job_type        => 'CHAIN',
		job_action      => 'chain_monthly_archive',
		schedule_name   => 'sch_monthly_arch_chain',
		enabled         => TRUE,
		comments        => 'Runs monthly archive and cleanup workflow on first day of each month'
	);
	
	DBMS_SCHEDULER.CREATE_JOB (
		job_name        => 'job_halfyear_archive_chain',
		job_type        => 'CHAIN',
		job_action      => 'chain_halfyear_archive',
		schedule_name   => 'sch_halfyear_archive_chain',
		enabled         => TRUE,
		comments        => 'Runs semiannual archive consolidation and historical cleanup process'
	);
	
END;
/


