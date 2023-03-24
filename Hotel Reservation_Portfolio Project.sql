USE MyProjects
DROP TABLE IF EXISTS FULL_DATA
GO

-- Data aggregation of multiple years

WITH CTE AS (
	SELECT * FROM booking_2018
	UNION ALL
	SELECT * FROM booking_2019
	UNION ALL
	SELECT * FROM booking_2020
)
-- Create a new table with all data that we need

SELECT CTE.*,
	MARKET.Discount,
	MEAL.Cost AS meal_cost
INTO FULL_DATA
FROM CTE 
	LEFT JOIN market_segment MARKET ON CTE.market_segment=MARKET.market_segment
	LEFT JOIN meal_cost MEAL ON CTE.meal=MEAL.meal
GO

-- Now we have a table with all relevant information  
-- 1. Look at the revenue and revenue percentage changes year over year

 WITH TEMP AS (
	SELECT hotel,
		arrival_date_year,
		ROUND(SUM((stays_in_weekend_nights + stays_in_week_nights) * adr * (1 -  Discount) + meal_cost), 0, 1) AS revenue
	FROM FULL_DATA
	WHERE is_canceled = 0
	GROUP BY hotel, arrival_date_year
	)

SELECT a.hotel,
	a.arrival_date_year AS current_year,
	a.revenue AS revenue_current_year,
	COALESCE(b.revenue, 0) AS revenue_previous_year,
	CASE 
		WHEN b.arrival_date_year IS NOT NULL 
		THEN ROUND(((a.revenue - b.revenue)/b.revenue) * 100, 2) 
		ELSE 0 END AS percentage_change
FROM TEMP a 
	LEFT JOIN TEMP b ON a.arrival_date_year=b.arrival_date_year + 1 AND a.hotel=b.hotel
ORDER BY hotel, current_year
GO

-- 2. Look at the highest and lowest revenue month of the year

WITH RANK_REVENUE AS (
	SELECT *,
		RANK() OVER(PARTITION BY  hotel, arrival_date_year  ORDER BY revenue_by_month DESC) AS rank_revenue_month
	FROM (
	SELECT hotel,
		arrival_date_year,
		arrival_date_month,
		ROUND(SUM((stays_in_week_nights + stays_in_weekend_nights) * adr * (1 - Discount) + meal_cost), 2) AS revenue_by_month
	FROM FULL_DATA
	WHERE is_canceled = 0
	GROUP BY hotel, arrival_date_year, arrival_date_month
	) TEMP )

SELECT A.hotel,
	A.year,
	A.month_with_highest_revenue,
	A.highest_revenue,
	B.month_with_lowest_revenue,
	B.lowest_revenue
FROM (
	SELECT hotel,
		arrival_date_year as year,
		arrival_date_month as month_with_highest_revenue,
		revenue_by_month AS highest_revenue
	FROM RANK_REVENUE
	WHERE rank_revenue_month = 1 ) A
	LEFT JOIN 
	(SELECT hotel,
		arrival_date_year as year,
		arrival_date_month as month_with_lowest_revenue,
		revenue_by_month AS lowest_revenue
	FROM RANK_REVENUE
	WHERE rank_revenue_month = 12) B
	ON A.hotel=B.hotel AND A.year=B.year
ORDER BY 1, 2
GO

-- 3. Find the average number of bookings per day

WITH CTE AS (
SELECT hotel,
	arrival_date_year,
	CONCAT(arrival_date_day_of_month, '-', arrival_date_month, '-', arrival_date_year) AS detail_date
FROM FULL_DATA
WHERE is_canceled = 0
)
SELECT hotel,
	arrival_date_year,
	CAST(ROUND(COUNT(*) * 1.0/COUNT(DISTINCT detail_date), 0))
FROM CTE
GROUP BY hotel, arrival_date_year			
		
-- 4. Look at the average daily rate (ADR) for the hotel

SELECT hotel,
	ROUND(SUM(adr) / COUNT(*), 2) AS average_daily_rate
FROM FULL_DATA
GROUP BY hotel

-- 5. Look at the overall cancellation rate for the hotel

SELECT hotel,
	CAST((SUM(is_canceled) / COUNT(*)) * 100 AS NUMERIC(5, 2)) AS cancellation_rate
FROM FULL_DATA
GROUP BY hotel
GO

-- 6. Look at the cancellation rate of bookings by day

SELECT hotel,
	arrival_date_year,
	arrival_date_month,
	arrival_date_day_of_month,
	SUM(is_canceled) AS total_cancellation,
	COUNT(*) AS total_bookings,
	CAST((SUM(is_canceled) * 1.0 / COUNT(*)) * 100 AS NUMERIC(4, 1)) AS rate_cancellation
FROM FULL_DATA
GROUP BY hotel,
	arrival_date_year,
	arrival_date_month,
	arrival_date_day_of_month
ORDER BY 1, 2
GO

-- 7. Look at TOP 3 countries:  Where do most of the guests come from?

WITH CTE AS (
	SELECT hotel,
		COUNT(*) AS total_bookings
	FROM FULL_DATA
	WHERE is_canceled != 1
	GROUP BY hotel
	)

SELECT H.hotel,
	country,
	country_bookings,
	total_bookings,
	CONCAT((CAST((country_bookings * 1.0 / total_bookings) * 100 AS NUMERIC(5, 1))), ' %') AS rating
FROM (
	SELECT *,
		RANK() OVER(PARTITION BY hotel ORDER BY country_bookings DESC) as rank_
	FROM (
		SELECT hotel,
			country,
			COUNT(*) AS country_bookings
		FROM FULL_DATA
		WHERE is_canceled != 1
		GROUP BY hotel, country
		) T) H
	LEFT JOIN CTE ON H.hotel=CTE.hotel
WHERE rank_ <= 3
GO
-- 8. Look at the type of meal that most guests chose

SELECT hotel,
	meal,
	choices,
	CONCAT(CAST((choices * 1.0 / SUM(choices) OVER (PARTITION BY hotel ORDER BY hotel)) * 100 AS NUMERIC(4, 2)), ' %') AS rating
FROM (
	SELECT hotel,
		meal,
		COUNT(*) AS choices
	FROM FULL_DATA
	WHERE is_canceled != 1
	GROUP BY hotel, meal
	) T
ORDER BY 2, 1
GO

-- 9. Look at which market segment most bookings come from

SELECT hotel,
	market_segment,
	total,
	CONCAT(CAST((total * 1.0 / SUM(total) OVER(PARTITION BY hotel ORDER BY hotel) * 100) AS NUMERIC(5, 2)), ' %') AS rating
FROM (
	SELECT hotel,
		market_segment,
		COUNT(*) AS total
	FROM FULL_DATA
	WHERE is_canceled = 0
	GROUP BY hotel, market_segment
	) T
ORDER BY 1, 4 DESC
GO

-- 10. Look at which distributions channels are the most prevelent 

SELECT hotel,
	distribution_channel,
	total,
	CONCAT(CAST((total * 1.0 / SUM(total) OVER(PARTITION BY hotel ORDER BY hotel) * 100) AS NUMERIC(5, 2)), ' %') AS rating
FROM (
	SELECT hotel,
		distribution_channel,
		COUNT(*) AS total
	FROM FULL_DATA
	WHERE is_canceled = 0
	GROUP BY hotel, distribution_channel
	) T
ORDER BY 1, 4 DESC
GO
