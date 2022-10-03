SET SEARCH_PATH TO postgres_air;

CREATE INDEX IF NOT EXISTS flight_departure_airport ON flight(departure_airport);
CREATE INDEX IF NOT EXISTS flight_scheduled_departure ON flight(scheduled_departure);
CREATE INDEX IF NOT EXISTS flight_update_ts ON flight(update_ts);
CREATE INDEX IF NOT EXISTS booking_leg_booking_id ON booking_leg(booking_leg_id);
CREATE INDEX IF NOT EXISTS booking_leg_update_ts ON booking_leg(update_ts);
CREATE INDEX IF NOT EXISTS account_last_name ON account(last_name);

-------------- Execution plan
-- There are 141 of airports in US
SELECT count(1) from airport where iso_country = 'US';
-- Full scan is used, as using index will not improve performance
EXPLAIN
SELECT flight_id, scheduled_departure
FROM flight f
         JOIN airport a on f.departure_airport = a.airport_code AND iso_country = 'US';
-- There are only 2 airport in NL.
SELECT count(1) from airport where iso_country = 'NL';
-- Index access is efficient
EXPLAIN
SELECT flight_id, scheduled_departure
FROM flight f
         JOIN airport a on f.departure_airport = a.airport_code AND iso_country = 'NL';

-------------- Data Access Algorithms
-- Wide range filtering query -> optimiser selects full table scan:
EXPLAIN
SELECT flight_no, departure_airport, arrival_airport
FROM flight
WHERE scheduled_departure BETWEEN '2019-01-01' AND '2022-01-01';

-- Smaller range of the same query -> might result in index-based table access:
EXPLAIN
SELECT flight_no, departure_airport, arrival_airport
FROM flight
WHERE scheduled_departure BETWEEN '2020-08-15' AND '2020-08-31';


-------------- Short vs. long queries
CREATE INDEX IF NOT EXISTS flight_arrival_airport ON flight  (arrival_airport);
CREATE INDEX IF NOT EXISTS booking_leg_flight_id ON booking_leg  (flight_id);
CREATE INDEX IF NOT EXISTS flight_actual_departure ON flight  (actual_departure);
CREATE INDEX IF NOT EXISTS boarding_pass_booking_leg_id ON postgres_air.boarding_pass  (booking_leg_id);

-- Short vs. long queries: length of SQL does not matter
-- Long query example. Needs all records from a table to compute the result
SELECT d.airport_code AS departuer_airport, a.airport_code AS arrival_airport
FROM airport a,
     airport d;

-- Short Query example. Needs to find a few specific entries, but across many tables and with specific conditions
SELECT f.flight_no,
       f.scheduled_departure,
       boarding_time,
       p.last_name,
       p.first_name,
       bp.update_ts as pass_issued,
       ff.level
FROM flight f
         JOIN booking_leg bl ON bl.flight_id = f.flight_id
         JOIN passenger p ON p.booking_id=bl.booking_id
         JOIN account a on a.account_id =p.account_id
         JOIN boarding_pass bp on bp.passenger_id=p.passenger_id
         LEFT OUTER JOIN frequent_flyer ff on ff.frequent_flyer_id=a.frequent_flyer_id
WHERE f.departure_airport = 'JFK'
  AND f.arrival_airport = 'ORD'
  AND f.scheduled_departure BETWEEN
    '2020-08-05' AND '2020-08-07';


-------------- Column transformations
CREATE INDEX IF NOT EXISTS account_last_name ON account(last_name);

-- column transformation forces to use full scan instead of utilizing an index
EXPLAIN
SELECT *
FROM account
WHERE lower(last_name) = 'daniels';

-- fix by rewriting a query:
EXPLAIN
SELECT *
FROM account
WHERE last_name = 'daniels'
   OR last_name = 'Daniels'
   or last_name = 'DANIELS';

-- or by creating a functional index on a column:
DROP INDEX IF EXISTS account_last_name_lower;
CREATE INDEX IF NOT EXISTS account_last_name_lower ON account (lower(last_name));

EXPLAIN
SELECT *
FROM account
WHERE lower(last_name) = 'daniels';

-- Functional index is not always needed:
EXPLAIN
SELECT *
FROM flight
WHERE scheduled_departure ::date BETWEEN '2020-08-17' AND '2020-08-18';
-- no need to convert timestamp to date:
EXPLAIN
SELECT *
FROM flight
WHERE scheduled_departure BETWEEN '2020-08-17' AND '2020-08-18';

-- COALESCE function - allows to use a different value when the first argument is null
-- Indexes cannot be utilized because COALESCE is a function
EXPLAIN
SELECT *
FROM flight
WHERE COALESCE(actual_departure, scheduled_departure) BETWEEN '2020-08-17' AND '2020-08-18';
-- Solution: rewrite query without using coalesce
EXPLAIN
SELECT *
FROM flight
WHERE (actual_departure BETWEEN '2020-08-17' AND '2020-08-18')
   OR (actual_departure IS NULL AND scheduled_departure BETWEEN '2020-08-17' AND '2020-08-18');


-------------- Indexes and the LIKE Operator
EXPLAIN
SELECT *
FROM account
WHERE lower(last_name) LIKE 'johns%';
-- Rewrite query to avoid using LIKE:
EXPLAIN
SELECT *
FROM account
WHERE lower(last_name) >= 'johns' and lower(last_name) < 'johnt';
-- Or create a pattern search index
DROP INDEX IF EXISTS account_last_name_lower_pattern;
CREATE INDEX IF NOT EXISTS account_last_name_lower_pattern ON account (LOWER(last_name) text_pattern_ops);
-- now index will be used:
EXPLAIN
SELECT *
FROM account
WHERE lower(last_name) LIKE 'johns%';



-------------- Using multiple & compound indexes
DROP INDEX IF EXISTS flight_depart_arr_sched_dep;

EXPLAIN
SELECT scheduled_departure,
       scheduled_arrival
FROM flight
WHERE departure_airport = 'JFK'
  AND arrival_airport = 'AMS'
  AND scheduled_departure BETWEEN '2020-07-03' AND '2020-07-04';

--  Can be more efficient by utilizing a compound index
CREATE INDEX IF NOT EXISTS flight_depart_arr_sched_dep ON
    flight (departure_airport,
            arrival_airport,
            scheduled_departure);

EXPLAIN
SELECT scheduled_departure,
       scheduled_arrival
FROM flight
WHERE departure_airport = 'JFK'
  AND arrival_airport = 'AMS'
  AND scheduled_departure BETWEEN '2020-07-03' AND '2020-07-04';



-------------- Using multiple & compound indexes
DROP INDEX IF EXISTS flight_depart_arr_sched_dep_inc_sched_arr;
CREATE INDEX flight_depart_arr_sched_dep_inc_sched_arr
    ON flight
        (departure_airport,
         arrival_airport,
         scheduled_departure)
    INCLUDE (scheduled_arrival);

-- Covering index includes `scheduled_arrival` column, that allows to perform index-only scan
EXPLAIN
SELECT scheduled_departure,
       scheduled_arrival
FROM flight
WHERE departure_airport = 'JFK'
  AND arrival_airport = 'AMS'
  AND scheduled_departure BETWEEN '2020-07-03' AND '2020-07-04';


-------------- Using Partial indexes
-- possible `status` values: ‘On schedule’, ‘Delayed’, and ‘Canceled’.
-- There are much more flights with a status 'On Schedule', creating an index on it will not be efficient due to high selectivity
-- But it makes sense to create an index on 'Canceled' column and benefit from low selectivity:
DROP INDEX IF EXISTS flight_canceled;
CREATE INDEX IF NOT EXISTS flight_canceled ON flight(flight_id)
    WHERE status='Canceled';

EXPLAIN
SELECT *
FROM flight
WHERE scheduled_departure between '2020-08-15' AND '2020-08-18'
  AND status = 'Canceled';




-------------- Indexes and Order of Joins
DROP INDEX IF EXISTS account_login;
DROP INDEX IF EXISTS account_login_lower_pattern;
DROP INDEX IF EXISTS passenger_last_name;
DROP INDEX IF EXISTS boarding_pass_passenger_id;
DROP INDEX IF EXISTS passenger_last_name_lower_pattern;
DROP INDEX IF EXISTS passenger_booking_id;
DROP INDEX IF EXISTS booking_account_id;

CREATE INDEX IF NOT EXISTS account_login ON account(login);
CREATE INDEX IF NOT EXISTS account_login_lower_pattern ON account  (lower(login) text_pattern_ops);
CREATE INDEX IF NOT EXISTS passenger_last_name ON passenger  (last_name);
CREATE INDEX IF NOT EXISTS boarding_pass_passenger_id ON boarding_pass  (passenger_id);
CREATE INDEX IF NOT EXISTS passenger_last_name_lower_pattern ON passenger  (lower(last_name) text_pattern_ops);
CREATE INDEX IF NOT EXISTS passenger_booking_id ON passenger(booking_id);
CREATE INDEX IF NOT EXISTS booking_account_id ON booking(account_id);

-- account table is smaller than passenger and booking (not every passenger has an account)
-- execution starts from the smaller table (account) when the selectivity is similar with passenger table
EXPLAIN
SELECT b.account_id,
       b.booking_ref,
       a.login,
       p.last_name,
       p.first_name
FROM passenger p
         JOIN booking b USING (booking_id)
         JOIN account a ON a.account_id = b.account_id
WHERE lower(p.last_name) = 'smith'
  AND lower(login) LIKE 'smith%';

--
DROP INDEX IF EXISTS frequent_fl_last_name_lower_pattern;
DROP INDEX IF EXISTS frequent_fl_last_name_lower;
CREATE INDEX IF NOT EXISTS frequent_fl_last_name_lower_pattern ON frequent_flyer (lower(last_name) text_pattern_ops);
CREATE INDEX IF NOT EXISTS frequent_fl_last_name_lower ON frequent_flyer (lower(last_name));

-- Query number of bookings for each frequent flyer: the execution will start from frequent_flyer as it is even smaller than account table (not every account is a frequent flyer)
EXPLAIN
SELECT a.account_id,
       a.login,
       f.last_name,
       f.first_name,
       count(*) AS num_bookings
FROM frequent_flyer f
         JOIN account a USING (frequent_flyer_id)
         JOIN booking b USING (account_id)
WHERE lower(f.last_name) = 'smith'
  AND lower(login) LIKE 'smith%'
GROUP BY 1, 2, 3, 4;










































