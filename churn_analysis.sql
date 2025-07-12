CREATE DATABASE Churn_Analysis;
USE Churn_Analysis;

-- Creating the tables and importing csv data

CREATE TABLE customers (
    customer_id VARCHAR(20) PRIMARY KEY,
    join_date DATE,
    plan_type ENUM('Basic', 'Standard', 'Premium'),
    is_active TINYINT(1)
);

CREATE TABLE usage_logs (
    customer_id VARCHAR(20),
    date DATE,
    minutes_used DECIMAL(10, 2),
    sessions INT,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE support_tickets (
    ticket_id VARCHAR(36) PRIMARY KEY,
    customer_id VARCHAR(20),
    date_opened DATE,
    resolved TINYINT(1),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE payments (
    customer_id VARCHAR(20),
    date DATE,
    amount DECIMAL(10, 2),
    status ENUM('Paid', 'Missed'),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- Having a look at the total customers, active vs. inactive
SELECT 
COUNT(*) AS total_customers,
SUM(is_active) AS active_customers,
COUNT(*) - SUM(is_active) AS churned_customers
FROM customers;


-- Churn Rate
SELECT 
ROUND(
	(COUNT(*) - SUM(is_active)) / COUNT(*) * 100, 2
) AS churn_rate_percentage
FROM customers;

-- Churn Rate by Plan Type 
SELECT 
plan_type,
COUNT(*) AS total,
SUM(is_active) AS active,
COUNT(*) - SUM(is_active) AS churned,
ROUND((COUNT(*) - SUM(is_active)) / COUNT(*) * 100, 2) AS churn_rate_percent
FROM customers
GROUP BY plan_type;

-- Average Usage per Customer
SELECT 
customer_id,
ROUND(AVG(minutes_used), 2) AS avg_minutes_used,
ROUND(AVG(sessions), 2) AS avg_sessions
FROM usage_logs
GROUP BY customer_id;

-- Average Minutes Used by Month
SELECT 
customer_id,
DATE_FORMAT(date, '%Y-%m') AS yearmonth,
ROUND(AVG(minutes_used), 2) AS avg_minutes
FROM usage_logs
GROUP BY customer_id, yearmonth
ORDER BY customer_id, yearmonth;

-- Customers who raised Support Tickets
SELECT 
COUNT(DISTINCT customer_id) AS ticket_raisers,
ROUND(COUNT(DISTINCT customer_id) / (SELECT COUNT(*) FROM customers) * 100, 2) AS percent_with_tickets
FROM support_tickets;

-- Average Support Tickets per Customer who raised them
SELECT 
customer_id,
COUNT(*) AS total_tickets
FROM support_tickets
GROUP BY customer_id
ORDER BY total_tickets DESC
LIMIT 10;

-- Missed Payments per Customers
SELECT 
customer_id,
COUNT(*) AS total_payments,
SUM(CASE WHEN status = 'Missed' THEN 1 ELSE 0 END) AS missed_payments,
ROUND(SUM(CASE WHEN status = 'Missed' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS missed_percent
FROM payments
GROUP BY customer_id
ORDER BY missed_percent DESC
LIMIT 10;

-- Churn Risk Segmentation 
SELECT
c.customer_id,
c.plan_type,
c.is_active,
COALESCE(u.avg_minutes_used, 0) AS avg_minutes_used,
COALESCE(p.missed_payments, 0) AS missed_payments,
COALESCE(s.ticket_count, 0) AS ticket_count,
    CASE
        WHEN COALESCE(u.avg_minutes_used, 0) < 150 AND COALESCE(p.missed_payments, 0) >= 3 THEN 'High Risk'
        WHEN COALESCE(u.avg_minutes_used, 0) BETWEEN 150 AND 250 
             OR COALESCE(p.missed_payments, 0) = 1
             OR COALESCE(s.ticket_count, 0) >= 2 THEN 'Medium Risk'
        ELSE 'Low Risk'
END AS churn_risk_segment

FROM customers c
LEFT JOIN (
    SELECT 
	customer_id,
	ROUND(AVG(minutes_used), 2) AS avg_minutes_used
    FROM usage_logs
    GROUP BY customer_id
) u ON c.customer_id = u.customer_id

LEFT JOIN (
    SELECT 
	customer_id,
	SUM(CASE WHEN status = 'Missed' THEN 1 ELSE 0 END) AS missed_payments
    FROM payments
    GROUP BY customer_id
) p ON c.customer_id = p.customer_id

LEFT JOIN (
    SELECT 
	customer_id,
	COUNT(*) AS ticket_count
    FROM support_tickets
    GROUP BY customer_id
) s ON c.customer_id = s.customer_id
ORDER BY churn_risk_segment, avg_minutes_used;

-- Churned vs. Retained comparison
SELECT 
c.is_active,
ROUND(AVG(u.minutes_used), 2) AS avg_minutes,
ROUND(AVG(p.missed), 2) AS avg_missed_payments,
ROUND(AVG(s.tickets), 2) AS avg_tickets
FROM customers c
LEFT JOIN (
    SELECT customer_id, AVG(minutes_used) AS minutes_used
    FROM usage_logs
    GROUP BY customer_id
) u ON c.customer_id = u.customer_id
LEFT JOIN (
    SELECT customer_id, SUM(CASE WHEN status = 'Missed' THEN 1 ELSE 0 END) AS missed
    FROM payments
    GROUP BY customer_id
) p ON c.customer_id = p.customer_id
LEFT JOIN (
    SELECT customer_id, COUNT(*) AS tickets
    FROM support_tickets
    GROUP BY customer_id
) s ON c.customer_id = s.customer_id
GROUP BY c.is_active;

-- Lifetime Revenue per Customer
SELECT 
customer_id,
SUM(amount) AS total_revenue,
COUNT(*) AS num_payments,
ROUND(SUM(amount)/COUNT(*), 2) AS avg_payment
FROM payments
WHERE status = 'Paid'
GROUP BY customer_id
ORDER BY total_revenue DESC;


-- Final View
CREATE VIEW churn_dashboard_view AS
SELECT
c.customer_id,
c.plan_type,
c.is_active,
COALESCE(u.avg_minutes_used, 0) AS avg_minutes_used,
COALESCE(p.total_revenue, 0) AS revenue,
COALESCE(p.missed_payments, 0) AS missed_payments,
COALESCE(s.ticket_count, 0) AS ticket_count,
    CASE
        WHEN COALESCE(u.avg_minutes_used, 0) < 150 AND COALESCE(p.missed_payments, 0) >= 3 THEN 'High Risk'
        WHEN COALESCE(u.avg_minutes_used, 0) BETWEEN 150 AND 250 THEN 'Medium Risk'
        ELSE 'Low Risk'
END AS churn_risk_segment
FROM customers c
LEFT JOIN (
    SELECT customer_id, ROUND(AVG(minutes_used), 2) AS avg_minutes_used
    FROM usage_logs
    GROUP BY customer_id
) u ON c.customer_id = u.customer_id
LEFT JOIN (
    SELECT 
	customer_id,
	SUM(CASE WHEN status = 'Missed' THEN 1 ELSE 0 END) AS missed_payments,
	SUM(CASE WHEN status = 'Paid' THEN amount ELSE 0 END) AS total_revenue
    FROM payments
    GROUP BY customer_id
) p ON c.customer_id = p.customer_id
LEFT JOIN (
    SELECT customer_id, COUNT(*) AS ticket_count
    FROM support_tickets
    GROUP BY customer_id
) s ON c.customer_id = s.customer_id;

SELECT * FROM churn_dashboard_view;






