/*

-- DROP USER LOTTO CASCADE;

-- USER SQL
CREATE USER LOTTO IDENTIFIED BY 123;

-- ADD ROLES
GRANT CONNECT TO LOTTO;
GRANT RESOURCE TO LOTTO;
GRANT CREATE JOB TO LOTTO;
GRANT CREATE ANY JOB TO LOTTO;
GRANT CREATE PROCEDURE TO LOTTO;
GRANT CREATE RULE TO LOTTO;
GRANT CREATE RULE SET TO LOTTO;
GRANT CREATE EVALUATION CONTEXT TO LOTTO;
GRANT EXECUTE ON DBMS_SCHEDULER TO LOTTO;
GRANT MANAGE SCHEDULER TO LOTTO;


*/
	--------------------------------------------------
	-- SEQUENCES
	--------------------------------------------------

CREATE SEQUENCE coupons_id_seq START WITH 1 INCREMENT BY 1 MAXVALUE 10000000 MINVALUE 1 CYCLE CACHE 20 ORDER;

CREATE SEQUENCE games_id_seq START WITH 10 INCREMENT BY 10 MINVALUE 10 NOCACHE ORDER;

	--------------------------------------------------
	-- TABLES
	--------------------------------------------------

CREATE TABLE games (
    game_id       		NUMBER(4) NOT NULL,
    game_name     		VARCHAR2(40 CHAR) NOT NULL,
    coupon_price  		NUMBER(5,2) NOT NULL,
	max_number 			NUMBER(2) NOT NULL,
    numbers_to_draw 	NUMBER(2) NOT NULL,
	jackpot				CHAR(1 CHAR) DEFAULT 'N',
	CONSTRAINT games_pk 
		PRIMARY KEY (game_id),
	CONSTRAINT jackpot_ck CHECK (jackpot IN ('Y', 'N'))
);

CREATE TABLE prize_rules (
    rule_id 			NUMBER(4) NOT NULL,
    game_id 			NUMBER(4) NOT NULL,
    matched_numbers 	NUMBER(2) NOT NULL,
    prize_amount 		NUMBER(10,2) NOT NULL,
	CONSTRAINT prize_rules_pk 
		PRIMARY KEY (rule_id),
    CONSTRAINT prize_game_fk
        FOREIGN KEY (game_id) REFERENCES games(game_id),
    CONSTRAINT game_match_un
        UNIQUE (game_id, matched_numbers)
);

CREATE TABLE coupons (
    coupon_id   NUMBER NOT NULL,
    coupon_at 	TIMESTAMP(0) NOT NULL,
    game_id     NUMBER(4) NOT NULL,
	CONSTRAINT coupons_pk 
		PRIMARY KEY (coupon_id),
	CONSTRAINT coupons_games_fk 
		FOREIGN KEY (game_id) REFERENCES games (game_id)
);

CREATE TABLE coupon_numbers (
    coupon_id 			NUMBER NOT NULL,
    selected_number 	NUMBER(2) NOT NULL,
	CONSTRAINT coupon_numbers_pk 
		PRIMARY KEY (coupon_id, selected_number),
	CONSTRAINT coupon_numbers_coupons_fk 
		FOREIGN KEY (coupon_id) REFERENCES coupons (coupon_id)
);

CREATE TABLE results (
    game_id   		NUMBER(4) NOT NULL,
    draw_at	  		TIMESTAMP(0) NOT NULL,
    drawn_number   	NUMBER(2) NOT NULL,
	draw_seq		NUMBER NOT NULL,
	CONSTRAINT results_pk 
		PRIMARY KEY (game_id, draw_at, drawn_number),
	CONSTRAINT results_games_fk FOREIGN KEY (game_id)
        REFERENCES games (game_id)
	
);

CREATE TABLE rollovers (
    game_id           	NUMBER(4) NOT NULL,
    rollover_at      	TIMESTAMP(0) NOT NULL,
    rollover_amount 	NUMBER(10,2) NOT NULL,
	CONSTRAINT rollovers_pk 
		PRIMARY KEY ( game_id, rollover_at),
	CONSTRAINT rollovers_games_fk FOREIGN KEY (game_id)
        REFERENCES games (game_id),
	CONSTRAINT rollover_amount_chk CHECK (rollover_amount <= 10000000)
);

CREATE TABLE top_winners (
    coupon_id     	NUMBER NOT NULL,
    prize_amount 	NUMBER(10,2) NOT NULL,
	CONSTRAINT top_winners_coupons_fk FOREIGN KEY (coupon_id)
        REFERENCES coupons (coupon_id),
	CONSTRAINT top_winners_coupon_id_un 
		UNIQUE (coupon_id)
);

CREATE TABLE winners_monthly_archive (
	game_id 			NUMBER(4) NOT NULL, 
	draw_at 			TIMESTAMP(0) NOT NULL, 
	matched_numbers 	NUMBER(2) NOT NULL,
    count_winners       NUMBER(10) NOT NULL,
	sum_prize_amount 	NUMBER(12,2) NOT NULL,
	CONSTRAINT winners_mon_arch_game_fk
		FOREIGN KEY (game_id) REFERENCES games(game_id),
    CONSTRAINT winners_mon_arch_un
        UNIQUE (game_id, draw_at,matched_numbers)
        
);

CREATE TABLE winners_archive (
	game_id 			NUMBER(4) NOT NULL, 
	period_start		DATE NOT NULL, 
    period_end 			DATE NOT NULL, 
	matched_numbers 	NUMBER(2) NOT NULL,
    sum_winners       	NUMBER(10) NOT NULL,
	total_prize_amount 	NUMBER(12,2) NOT NULL,
	CONSTRAINT winners_archive_game_fk
		FOREIGN KEY (game_id) REFERENCES games(game_id),
	CONSTRAINT winners_archive_un
		UNIQUE (game_id, period_start, period_end, matched_numbers)
);

CREATE TABLE guest_coupon_limits (
    request_date  DATE          NOT NULL,
    coupon_count  NUMBER(2)     DEFAULT 0 NOT NULL,
    CONSTRAINT guest_limits_pk 
		PRIMARY KEY (request_date),
    CONSTRAINT guest_limits_count_ck 
		CHECK (coupon_count <= 5)
);

	--------------------------------------------------
	-- INDEXES
	--------------------------------------------------
	
CREATE INDEX coupons_game_coupon_at_ix
	ON coupons (game_id, coupon_at);

CREATE INDEX results_game_draw_at_ix
	ON results (game_id, draw_at);

CREATE INDEX coupon_numbers_coupon_id_ix
	ON coupon_numbers (coupon_id);	
	
CREATE INDEX top_winners_coupon_id_ix
    ON top_winners (coupon_id);
	
	--------------------------------------------------
	-- COMMENTS
	--------------------------------------------------
	
COMMENT ON TABLE games IS
'Stores lottery game definitions, configuration and current jackpot settings';
COMMENT ON COLUMN games.game_id IS
'Unique identifier of lottery game';
COMMENT ON COLUMN games.game_name IS
'Display name of lottery game';
COMMENT ON COLUMN games.coupon_price IS
'Price of single coupon submission';
COMMENT ON COLUMN games.max_number IS
'Highest selectable number allowed in the game';
COMMENT ON COLUMN games.numbers_to_draw IS
'Amount of numbers selected and drawn per lottery round';
COMMENT ON COLUMN games.jackpot IS
'Indicates whether jackpot rollover is enabled for the game';


COMMENT ON TABLE prize_rules IS
'Defines payout amounts based on number of matched numbers per game';
COMMENT ON COLUMN prize_rules.rule_id IS
'Unique identifier of prize rule';
COMMENT ON COLUMN prize_rules.game_id IS
'Reference to lottery game';
COMMENT ON COLUMN prize_rules.matched_numbers IS
'Required number of matched numbers to qualify for payout';
COMMENT ON COLUMN prize_rules.prize_amount IS
'Fixed payout assigned to prize rule';


COMMENT ON TABLE coupons IS
'Stores generated lottery coupons submitted for a specific game';
COMMENT ON COLUMN coupons.coupon_id IS
'Unique identifier of lottery coupon';
COMMENT ON COLUMN coupons.coupon_at IS
'Timestamp when coupon was generated';
COMMENT ON COLUMN coupons.game_id IS
'Reference to lottery game';


COMMENT ON TABLE coupon_numbers IS
'Stores selected numbers assigned to each lottery coupon';
COMMENT ON COLUMN coupon_numbers.coupon_id IS
'Reference to lottery coupon';
COMMENT ON COLUMN coupon_numbers.selected_number IS
'Number selected as part of coupon submission';


COMMENT ON TABLE results IS
'Stores official drawn numbers for each lottery draw';
COMMENT ON COLUMN results.game_id IS
'Reference to lottery game';
COMMENT ON COLUMN results.draw_at IS
'Timestamp of lottery draw execution';
COMMENT ON COLUMN results.drawn_number IS
'Official number drawn during lottery round';
COMMENT ON COLUMN results.draw_seq IS
'Official number of draw lottery round';

COMMENT ON TABLE rollovers IS
'Stores active jackpot rollover amounts for jackpot-enabled games';
COMMENT ON COLUMN rollovers.game_id IS
'Reference to lottery game';
COMMENT ON COLUMN rollovers.rollover_at IS
'Timestamp of lottery draw execution';
COMMENT ON COLUMN rollovers.rollover_amount IS
'Current accumulated jackpot amount (max 10000000)';


COMMENT ON TABLE top_winners IS
'Stores jackpot or high-tier winning coupons preserved for long-term historical tracking';
COMMENT ON COLUMN top_winners.coupon_id IS
'Reference to winning coupon';
COMMENT ON COLUMN top_winners.prize_amount IS
'Calculated payout amount assigned to winning coupon';


COMMENT ON TABLE winners_monthly_archive IS
'Stores monthly archived winner statistics aggregated by game, draw date and matched numbers';
COMMENT ON COLUMN winners_monthly_archive.game_id IS
'Reference to the related lottery game';
COMMENT ON COLUMN winners_monthly_archive.draw_at IS
'Lottery draw timestamp included in monthly archive';
COMMENT ON COLUMN winners_monthly_archive.matched_numbers IS
'Number of correctly matched numbers for archived winners';
COMMENT ON COLUMN winners_monthly_archive.count_winners IS
'Total number of winners for given game, draw and match category';
COMMENT ON COLUMN winners_monthly_archive.sum_prize_amount IS
'Aggregated prize amount paid to winners for given archive record';


COMMENT ON TABLE winners_archive IS
'Stores long-term aggregated archive of winner statistics for historical retention';
COMMENT ON COLUMN winners_archive.game_id IS
'Reference to the related lottery game';
COMMENT ON COLUMN winners_archive.period_start IS
'Start date of archived aggregation period';
COMMENT ON COLUMN winners_archive.period_end IS
'End date of archived aggregation period';
COMMENT ON COLUMN winners_archive.matched_numbers IS
'Number of correctly matched numbers included in archive summary';
COMMENT ON COLUMN winners_archive.sum_winners IS
'Aggregated number of winners within archived period';
COMMENT ON COLUMN winners_archive.total_prize_amount IS
'Total prize amount aggregated for archived period and match category';

COMMENT ON TABLE guest_coupon_limits IS
'Stores daily coupon generation statistics for guest users to prevent excessive coupon creation and control system resource usage.';
COMMENT ON COLUMN guest_coupon_limits.request_date IS
'Calendar date for which guest coupon generation activity is recorded.';
COMMENT ON COLUMN guest_coupon_limits.coupon_count IS
'Total number of coupons generated by guest users on the specified date. The value is limited to five coupons per day.';

	--------------------------------------------------
	-- DATA
	--------------------------------------------------

INSERT INTO GAMES (GAME_ID,GAME_NAME,COUPON_PRICE,MAX_NUMBER,NUMBERS_TO_DRAW,JACKPOT) 
VALUES (10,'Big Lotto',	'2', 49, 6, 'Y');
INSERT INTO GAMES (GAME_ID,GAME_NAME,COUPON_PRICE,MAX_NUMBER,NUMBERS_TO_DRAW,JACKPOT) 
VALUES (20,'Express Lotto','1.5', 42, 5,'N');

INSERT INTO prize_rules VALUES (1, 10, 3, 24);
INSERT INTO prize_rules VALUES (2, 10, 4, 200);
INSERT INTO prize_rules VALUES (3, 10, 5, 5300);
INSERT INTO prize_rules VALUES (4, 10, 6, 100000);


INSERT INTO prize_rules VALUES (6, 20, 3, 50);
INSERT INTO prize_rules VALUES (7, 20, 4, 1200);
INSERT INTO prize_rules VALUES (8, 20, 5, 100000);

COMMIT;
 
 
 


