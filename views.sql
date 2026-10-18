CREATE OR REPLACE VIEW matched_winners AS
SELECT 
    g.game_id, r.draw_at, c.coupon_at, c.coupon_id, COUNT(*) matched_numbers 
FROM results r
JOIN games g
    ON r.game_id = g.game_id
JOIN coupons c
    ON c.game_id = g.game_id
    AND c.coupon_at BETWEEN r.draw_at - (INTERVAL '1' DAY)  AND r.draw_at
JOIN coupon_numbers cn
    ON c.coupon_id=cn.coupon_id
WHERE cn.selected_number = r.drawn_number
GROUP BY g.game_id, g.game_name, r.draw_at, c.coupon_id, c.coupon_at
HAVING COUNT(*) >= 3;


CREATE OR REPLACE  VIEW winners_with_amount AS
SELECT mw.*,
   NVL(tw.prize_amount, pr.prize_amount) AS prize_amount       
FROM matched_winners mw
LEFT JOIN top_winners tw
	ON mw.coupon_id=tw.coupon_id
LEFT JOIN prize_rules pr
	ON pr.game_id = mw.game_id
	AND pr.matched_numbers = mw.matched_numbers;


CREATE OR REPLACE VIEW winning_numbers AS 
SELECT
	game_id, draw_at, no_1, no_2, no_3, no_4, no_5,  no_6
FROM 
  (SELECT
  game_id, drawn_number, draw_at draw_at,
  ROW_NUMBER()
  OVER(PARTITION BY draw_at, game_id
  ORDER BY drawn_number ASC )  rn
  FROM results )
PIVOT (
  MAX ( drawn_number )FOR rn IN ( 1 no_1, 2 no_2, 3 no_3, 4 no_4, 5 no_5, 6 no_6 )
  );
 

	--------------------------------------------------
	-- GUEST USER VIEWS
	--------------------------------------------------
 
CREATE OR REPLACE VIEW v_recent_winning_numbers AS
SELECT *
FROM winning_numbers
WHERE draw_at >= SYSTIMESTAMP - INTERVAL '7' DAY
WITH READ ONLY;

CREATE OR REPLACE VIEW v_recent_winners_with_amount AS
SELECT *
FROM winners_with_amount
WHERE draw_at >= SYSTIMESTAMP - INTERVAL '7' DAY
WITH READ ONLY;

CREATE OR REPLACE VIEW v_recent_rollovers AS
SELECT *
FROM rollovers
WHERE rollover_at >= SYSTIMESTAMP - INTERVAL '7' DAY
WITH READ ONLY;

