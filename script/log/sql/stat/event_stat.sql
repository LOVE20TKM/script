SELECT
  contract_name,
  event_name,
  COUNT(*) AS count
FROM
  events
GROUP BY
  contract_name,
  event_name
ORDER BY
  count DESC;

select contract_name,count(distinct "to") as unique_to_addresses
from v_transfer
group by contract_name
order by unique_to_addresses desc;

select round, count(distinct "to") as unique_to_addresses
from v_transfer
where contract_name = 'LOVE20'
group by round
order by round desc;

select contract_name,count(distinct "from") as unique_from_addresses
from v_transfer
group by contract_name
order by unique_from_addresses desc;