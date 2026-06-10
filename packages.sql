	--------------------------------------------------
    -- MAIN PACKAGE
    --------------------------------------------------
CREATE OR REPLACE PACKAGE lotto_pkg IS  
    --------------------------------------------------
    -- CONSTANTS
    --------------------------------------------------
	c_big_lotto     	CONSTANT NUMBER := 10;
	c_express_lotto 	CONSTANT NUMBER := 20;
	c_max_rollover	 	CONSTANT NUMBER := 10000000;
	
    --------------------------------------------------
    -- TYPES
    --------------------------------------------------	
	SUBTYPE t_game IS games%ROWTYPE;   
	TYPE numbers_array IS TABLE OF NUMBER;
	
	--------------------------------------------------
    -- PUBLIC API
    --------------------------------------------------
	-- Generates coupon from manually provided numbers
	PROCEDURE generate_coupon (p_numbers IN numbers_array, p_game_id IN games.game_id%TYPE );
    -- Generates random valid coupon for selected game
	PROCEDURE generate_random_coupon(p_game_id IN games.game_id%TYPE);
	-- Performs official lottery draw for selected game
	PROCEDURE draw_numbers(p_game_id IN games.game_id%TYPE);	
	-- Calculates winners, payouts and jackpot rollovers
	PROCEDURE calculate_winners(p_game_id IN games.game_id%TYPE);
	-- Archives last month's draw results into winners_monthly_archive
	PROCEDURE create_mon_arch;
	-- Deletes non-winning coupons and orphaned results (called after create_mon_arch)
	PROCEDURE clean_mon_data;
	-- Aggregates monthly archive into semi-annual winners_archive
	PROCEDURE create_halfyear_archive;

END lotto_pkg;
/



	--------------------------------------------------
    -- GUEST PACKAGE
    --------------------------------------------------
CREATE OR REPLACE PACKAGE guest_pkg IS
    TYPE number_list IS TABLE OF NUMBER;
    PROCEDURE guest_generate_coupon(
        p_numbers IN number_list,
        p_game_id IN games.game_id%TYPE
    );
END guest_pkg;
/





CREATE OR REPLACE PACKAGE BODY lotto_pkg IS  
    --------------------------------------------------
    -- PRIVATE TYPES
    --------------------------------------------------
	TYPE rolled_no IS TABLE OF NUMBER INDEX BY PLS_INTEGER;

    --------------------------------------------------
    -- PRIVATE FUNCTION DECLARATIONS
    --------------------------------------------------
	FUNCTION get_game(p_game_id IN games.game_id%TYPE) RETURN t_game;	
	FUNCTION calculate_winners_prize_sum (p_day IN results.draw_at%TYPE, p_game_id IN games.game_id%TYPE) RETURN NUMBER;	
	FUNCTION count_top_winners (p_day IN results.draw_at%TYPE, p_game_id IN games.game_id%TYPE) RETURN NUMBER;
	FUNCTION get_next_draw_seq(p_game_id IN games.game_id%TYPE) RETURN NUMBER;


    --------------------------------------------------
    -- COUPON OPERATIONS
    --------------------------------------------------
	
	PROCEDURE generate_coupon (p_numbers IN numbers_array,   p_game_id IN games.game_id%TYPE )   IS
		v_coupon_id 		coupons.coupon_id%TYPE;
		v_game_rec 			t_game;
		v_un_count 			NUMBER;
		v_now				coupons.coupon_at%TYPE;
	BEGIN
		v_now 		:=		SYSTIMESTAMP;
		v_game_rec 	:=		get_game(p_game_id);		
		
		--------------------------------------------------
		-- VALIDATE INPUT NUMBERS
		--------------------------------------------------
		
		IF p_numbers.COUNT != v_game_rec.numbers_to_draw THEN
			RAISE_APPLICATION_ERROR(-20002, 'Invalid amount of selected numbers');
		END IF;
		
		SELECT COUNT(DISTINCT column_value) INTO v_un_count FROM TABLE(p_numbers);
		
		IF v_un_count != p_numbers.COUNT THEN
			RAISE_APPLICATION_ERROR(-20003,'Duplicate numbers are not allowed');
		END IF;
		
		FOR i IN 1 .. p_numbers.COUNT
		LOOP
			IF p_numbers(i) < 1
			OR p_numbers(i) > v_game_rec.max_number THEN
				RAISE_APPLICATION_ERROR(-20001, 'Invalid numbers');
			END IF;
		END LOOP;		
		
		--------------------------------------------------
		-- CREATE COUPON HEADER
		--------------------------------------------------
				
		INSERT INTO coupons (coupon_id, coupon_at,game_id)		
		VALUES (CONCAT(TO_NUMBER(TO_CHAR(v_now, 'YYMMDD')),coupons_id_seq.nextval), v_now, p_game_id)
		RETURNING coupon_id
		INTO v_coupon_id;
		
		--------------------------------------------------
		-- STORE COUPON NUMBERS
		--------------------------------------------------
		
		FOR i IN 1 .. p_numbers.COUNT 
		LOOP
			INSERT INTO coupon_numbers (coupon_id, selected_number)
			VALUES (v_coupon_id,p_numbers(i) );
		END LOOP;

	END generate_coupon;


	PROCEDURE generate_random_coupon (p_game_id IN games.game_id%TYPE)
	IS
		v_game_rec 		t_game;
		v_coupon_id 	coupons.coupon_id%TYPE;
		v_now			coupons.coupon_at%TYPE;
	BEGIN
		v_game_rec 	:= 		get_game(p_game_id);
		v_now 		:=		SYSTIMESTAMP;

		--------------------------------------------------
		-- CREATE COUPON HEADER
		--------------------------------------------------
		INSERT INTO coupons (coupon_id, coupon_at, game_id) 
		VALUES (CONCAT(TO_NUMBER(TO_CHAR(v_now, 'YYMMDD')),coupons_id_seq.nextval),v_now, v_game_rec.game_id) 
		RETURNING coupon_id INTO v_coupon_id;

		--------------------------------------------------
		-- STORE COUPON NUMBERS
		--------------------------------------------------
		INSERT INTO coupon_numbers (coupon_id,selected_number )
		SELECT v_coupon_id, number_value
		FROM (
			SELECT LEVEL AS number_value
			FROM dual
			CONNECT BY LEVEL <= v_game_rec.max_number
			ORDER BY DBMS_RANDOM.VALUE
		)
		FETCH FIRST v_game_rec.numbers_to_draw ROWS ONLY;

	END generate_random_coupon;


    --------------------------------------------------
    -- DRAW OPERATIONS
    --------------------------------------------------

	PROCEDURE draw_numbers(p_game_id IN games.game_id%TYPE) 
	IS
		v_no_list     		VARCHAR2(30) DEFAULT '';
		v_index        		NUMBER DEFAULT 1;
		v_drawn_number      NUMBER;
		v_draw_seq 			NUMBER;
		v_now				results.draw_at%TYPE;
		v_game_rec 			t_game;
	BEGIN
		v_game_rec 	:=		get_game(p_game_id);
		v_draw_seq 	:=		get_next_draw_seq(v_game_rec.game_id);
		v_now		:= 		SYSTIMESTAMP;
		LOOP
			v_drawn_number := TRUNC(dbms_random.value(1,v_game_rec.max_number +1));

			IF INSTR(v_no_list, ',' || v_drawn_number || ',') > 0 THEN
				CONTINUE;
			END IF;

			INSERT INTO results(game_id, draw_at, drawn_number, draw_seq)
			VALUES (v_game_rec.game_id, v_now, v_drawn_number, v_draw_seq);
			
			v_no_list  := NVL(v_no_list , ',') || v_drawn_number || ',';
			v_index := v_index +1;
			
			EXIT WHEN v_index > v_game_rec.numbers_to_draw;		
		END LOOP;
	END draw_numbers;

    --------------------------------------------------
    -- PAYOUT OPERATIONS
    --------------------------------------------------

	PROCEDURE calculate_winners(p_game_id IN games.game_id%TYPE)
	IS
		v_now					results.draw_at%TYPE;
		v_max_winners   		NUMBER; 
		v_total_prize_amount    NUMBER; 
		v_rollover_amount		NUMBER DEFAULT NULL; 
		v_winners_prize_sum		NUMBER; 
		v_game_rec				t_game; 
	BEGIN
		--------------------------------------------------
		-- LOAD GAME CONFIGURATION
		--------------------------------------------------
		v_now	 				:= 	SYSTIMESTAMP;
		v_game_rec 				:=	get_game(p_game_id);			
		v_winners_prize_sum 	:= 	calculate_winners_prize_sum(v_now, v_game_rec.game_id);
		v_max_winners 			:= 	count_top_winners (v_now, v_game_rec.game_id);

		--------------------------------------------------
		-- LOAD CURRENT JACKPOT / ROLLOVER
		--------------------------------------------------
		IF UPPER(v_game_rec.jackpot) = 'Y' THEN
			BEGIN
				SELECT rollover_amount INTO v_rollover_amount FROM rollovers 
				WHERE  game_id = v_game_rec.game_id 
				ORDER BY rollover_at DESC
				FETCH FIRST 1 ROWS ONLY;
			
			EXCEPTION WHEN NO_DATA_FOUND THEN 
				SELECT MAX(prize_amount) INTO v_rollover_amount FROM prize_rules
				WHERE game_id = v_game_rec.game_id ;
			END; 
		END IF;		
		
		SELECT 
			CASE WHEN prize_amount - v_winners_prize_sum < 0 THEN 0 
			ELSE prize_amount - v_winners_prize_sum END
			INTO v_total_prize_amount 
		FROM prize_rules 
		WHERE game_id = v_game_rec.game_id
		AND matched_numbers = v_game_rec.numbers_to_draw; 


		--------------------------------------------------
		-- PROCESS TOP WINNERS
		--------------------------------------------------
		IF v_max_winners > 0 THEN 
		
			INSERT INTO top_winners (coupon_id, prize_amount)
			SELECT 
				mw.coupon_id,  
				ROUND((NVL(v_rollover_amount - v_winners_prize_sum, v_total_prize_amount)) / v_max_winners, 2) AS prize_amount FROM matched_winners mw
			WHERE mw.game_id = v_game_rec.game_id
			AND mw.matched_numbers = v_game_rec.numbers_to_draw
			AND	TO_CHAR(mw.draw_at, 'YYYYMMDD HH24') = TO_CHAR(v_now, 'YYYYMMDD HH24');	
			
			-- Clear Rollovers
			DELETE FROM rollovers WHERE game_id = v_game_rec.game_id;
		END IF;
		
		--------------------------------------------------
		-- HANDLE ROLLOVER AFTER DRAW
		--------------------------------------------------
		IF v_max_winners = 0 AND UPPER(v_game_rec.jackpot) = 'Y' THEN 	
		
			INSERT INTO rollovers(game_id, rollover_at, rollover_amount)
			VALUES (v_game_rec.game_id, v_now, 
				CASE WHEN v_rollover_amount + v_total_prize_amount > c_max_rollover THEN c_max_rollover 
				ELSE v_rollover_amount + v_total_prize_amount 
				END
				);				
		END IF;

	END calculate_winners;
	
	--------------------------------------------------
	-- ARCHIVE
	--------------------------------------------------
	
	-- Monthly Archive
	PROCEDURE create_mon_arch
	IS
		v_now results.draw_at%TYPE;
	BEGIN
		v_now := SYSTIMESTAMP;

		INSERT INTO winners_monthly_archive (
			SELECT game_id, draw_at , matched_numbers, COUNT(*) AS cnt_winners, SUM(prize_amount) AS sum_prize
			FROM winners_with_amount
			WHERE draw_at >= TRUNC(ADD_MONTHS(v_now, -1), 'MM')
			AND draw_at < TRUNC(v_now, 'MM')
			GROUP BY game_id, draw_at , matched_numbers);

	END;
	
	
	-- Monthly Clean Data
	PROCEDURE clean_mon_data
	IS
	BEGIN
		
		DELETE FROM coupon_numbers cn
		WHERE NOT EXISTS (
			SELECT 1
			FROM top_winners tw
			WHERE tw.coupon_id = cn.coupon_id
		);

		DELETE FROM coupons c
		WHERE NOT EXISTS (
			SELECT 1
			FROM top_winners tw
			WHERE tw.coupon_id = c.coupon_id
		);

		DELETE FROM results r
		WHERE NOT EXISTS (
			SELECT 1
			FROM coupons c
			JOIN top_winners tw
			ON tw.coupon_id = c.coupon_id
			WHERE c.game_id = r.game_id
			AND c.coupon_at BETWEEN r.draw_at - INTERVAL '1' DAY AND r.draw_at
		);
		
		DELETE FROM guest_coupon_limits 
		WHERE request_date != TRUNC(SYSDATE);
		
	END;
	
	
	-- Half-year Archive
	PROCEDURE create_halfyear_archive
	IS
		v_period_start    winners_archive.period_start%TYPE;
		v_period_end      winners_archive.period_end%TYPE;
	BEGIN
	
		SELECT MIN(draw_at), MAX(draw_at) INTO v_period_start, v_period_end FROM winners_monthly_archive;

		INSERT INTO winners_archive ( SELECT game_id, v_period_start, v_period_end, matched_numbers, SUM(count_winners), SUM(sum_prize_amount) FROM winners_monthly_archive
		GROUP BY game_id, matched_numbers);

	END;
	
    --------------------------------------------------
    -- PRIVATE HELPERS
    --------------------------------------------------

	FUNCTION get_game(p_game_id IN games.game_id%TYPE)
	RETURN t_game 
	IS
		v_rec 	t_game;
	BEGIN
			SELECT 
				game_id, game_name, coupon_price, max_number, numbers_to_draw, jackpot 
			INTO v_rec FROM games
			WHERE game_id = p_game_id;
			
			RETURN v_rec;
			
	EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20004, 'Game not found');		

	END get_game;


	FUNCTION calculate_winners_prize_sum (p_day IN results.draw_at%TYPE, p_game_id IN games.game_id%TYPE) 
	RETURN NUMBER 
	IS
		v_game_rec				t_game;
		v_winners_prize_sum 	NUMBER;
	BEGIN
		v_game_rec 	:=		get_game(p_game_id);

		SELECT NVL(SUM(prize_amount), 0) amount_summary INTO v_winners_prize_sum FROM winners_with_amount
		WHERE game_id = p_game_id
		AND matched_numbers < v_game_rec.numbers_to_draw
		AND TO_CHAR(draw_at, 'YYYYMMDD HH24') = TO_CHAR(p_day, 'YYYYMMDD HH24');
		
		RETURN v_winners_prize_sum;

	END calculate_winners_prize_sum;


	FUNCTION count_top_winners (p_day IN results.draw_at%TYPE, p_game_id IN games.game_id%TYPE)
	RETURN NUMBER 
	IS
		v_game_rec		t_game;
		v_winners_cnt 	NUMBER;
	BEGIN

		v_game_rec :=	get_game(p_game_id);
		SELECT COUNT(*) INTO v_winners_cnt FROM matched_winners
		WHERE game_id = p_game_id
		AND matched_numbers = v_game_rec.numbers_to_draw
		AND TO_CHAR(draw_at, 'YYYYMMDD HH24') = TO_CHAR(p_day, 'YYYYMMDD HH24');
		
		RETURN NVL(v_winners_cnt,0);

	END count_top_winners;
	
	
	FUNCTION get_next_draw_seq(p_game_id IN games.game_id%TYPE) RETURN NUMBER
	IS
		v_draw_seq results.draw_seq%TYPE;
	BEGIN
		SELECT NVL(MAX(draw_seq), 0) + 1
		INTO v_draw_seq
		FROM results
		WHERE game_id = p_game_id;
		
		RETURN v_draw_seq;
		
	END get_next_draw_seq;


END lotto_pkg;
/






CREATE OR REPLACE PACKAGE BODY guest_pkg IS

	PROCEDURE guest_generate_coupon(
		p_numbers  IN number_list,
		p_game_id  IN games.game_id%TYPE
	)
	AS
		v_converted lotto_pkg.numbers_array := lotto_pkg.numbers_array();
		v_today     DATE := TRUNC(SYSDATE);
		v_count     NUMBER;
	BEGIN
		BEGIN
			SELECT coupon_count INTO v_count
			FROM guest_coupon_limits
			WHERE request_date = v_today
			FOR UPDATE;

		EXCEPTION WHEN NO_DATA_FOUND THEN
			INSERT INTO guest_coupon_limits (request_date, coupon_count)
			VALUES (v_today, 0);
			v_count := 0;
		END;

		IF v_count >= 5 THEN
			RAISE_APPLICATION_ERROR(-20005,
				'Daily coupon limit reached. Maximum 5 coupons per day.');
		END IF;

		v_converted.EXTEND(p_numbers.COUNT);
		FOR i IN 1 .. p_numbers.COUNT 
		LOOP
			v_converted(i) := p_numbers(i);
		END LOOP;

		lotto_pkg.generate_coupon(
			p_numbers => v_converted,
			p_game_id => p_game_id
		);

		UPDATE guest_coupon_limits
		SET    coupon_count = coupon_count + 1
		WHERE  request_date = v_today;
		
		COMMIT;
	END guest_generate_coupon;

END guest_pkg;
/