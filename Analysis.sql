--
-- Часть 1. Знакомство с данными
--Проверим количество записей в трёх таблицах.
--Ожидаемое количество строк: visits_log — 359 400, orders_log — 50 415, costs — 2 542.


--1.1. Таблица visits_log (визиты)
--
select count(*)
from visits_log;

--Результат:
--count |
--------+
--359400|



--1.2. Таблица orders_log (заказы)
--
select count (*)
from orders_log;

--Результат:
--count|
-------+
--50415|



--1.3. Таблица costs (рекламные расходы)
--
select count (*)
from costs;

--Результат:
--count|
-------+
-- 2542|



--1.4. Типы данных
--
-- Проверим типы столбцов в схеме public.
-- Для расчётов даты должны иметь тип date или timestamp,
-- денежные значения — numeric.
-- Uid храним как text: часть идентификаторов превышает диапазон bigint.

select table_name, column_name, data_type
from information_schema."columns"
where table_schema = 'public';
--
--Результат:
--table_name|column_name|data_type                  |
------------+-----------+---------------------------+
--costs     |costs      |numeric                    |
--visits_log|End Ts     |timestamp without time zone|
--visits_log|Source Id  |integer                    |
--visits_log|Start Ts   |timestamp without time zone|
--orders_log|Revenue    |numeric                    |
--costs     |source_id  |integer                    |
--costs     |dt         |date                       |
--orders_log|Buy Ts     |timestamp without time zone|
--visits_log|Uid        |text                       |
--orders_log|Uid        |text                       |
--visits_log|Device     |character varying          |



--
-- Часть 2. Канал первого визита и размер аудитории
--Определим канал каждого пользователя и посмотрим, какую аудиторию даёт каждый канал.
--


--2.1. Первый визит каждого пользователя
--
-- Определим время и канал первого визита каждого пользователя
-- в доступной истории и сохраним их для дальнейших расчётов.
--
create view first_visit_channels as
select distinct on ("Uid") "Source Id", "Start Ts", "Uid"
from visits_log
order by "Uid", "Start Ts";

--Результат: одна строка на пользователя (канал, время и Uid первого визита).
--Первые строки:
--Source Id|Start Ts               |Uid                 |
-----------+-----------------------+--------------------+
--        3|2017-12-01 15:11:00.000|10000171586432207426|
--        3|2018-02-21 16:01:00.000|10000344846682484395|
--        3|2017-09-05 20:22:00.000|1000036778515242839 |
--        4|2017-09-13 09:12:00.000|10000460875579931334|
--Всего строк: 228169



--2.2. DAU по каналам (уникальные пользователи в день)
--
select f."Source Id", v."Start Ts"::date as "Day", count(distinct v."Uid") as "Unique users"
from first_visit_channels as f
join visits_log as v
on f."Uid" = v."Uid"
group by "Day", f."Source Id"
order by "Day";

--Результат:
--Первые строки:
--Source Id|Day     |Unique users|
-----------+----------+------------+
--        1|2017-06-01|          47|
--        2|2017-06-01|          70|
--        3|2017-06-01|         180|
--        4|2017-06-01|         137|
--Всего строк: 2,579



--2.3. MAU по каналам (уникальные пользователи в месяц)
--
select f."Source Id", date_trunc('month', v."Start Ts")::date as "Month", count(distinct v."Uid") as "Unique users"
from first_visit_channels as f
join visits_log as v
on f."Uid" = v."Uid"
group by "Month", f."Source Id"
order by "Month";

--Результат:
--Первые строки:
--Source Id|Month     |Unique users|
-----------+----------+------------+
--        1|2017-06-01|         631|
--        2|2017-06-01|        1262|
--        3|2017-06-01|        4080|
--        4|2017-06-01|        3447|
--        5|2017-06-01|        2728|
--        7|2017-06-01|           2|
--        9|2017-06-01|         713|
--       10|2017-06-01|         396|
--Всего строк: 98

--
-- Часть 3. Возвращаемость пользователей
--Проверим, возвращаются ли новые пользователи и какая часть аудитории пропускает следующий месяц.
--

--3.1. Monthly Retention (доля новичков, вернувшихся в следующем месяце)
--
-- Для мая 2018 возвращаем NULL: нет данных за следующий месяц — июнь.
--
select f."Source Id", date_trunc('month', f."Start Ts")::date as "First visit month",
case
	when date_trunc('month', f."Start Ts")::date + interval '1 month' > (select max ("Start Ts") from visits_log)
	then null
	else round (100.0 * count(distinct v."Uid") / count(distinct f."Uid"), 1) 
end as "Retention percent"
from first_visit_channels as f
left join visits_log as v
on f."Uid" = v."Uid" 
and date_trunc('month', f."Start Ts")::date + interval '1 month' = date_trunc('month', v."Start Ts")::date
group by f."Source Id", "First visit month"
order by "First visit month";

--Результат:
--Первые строки:
--Source Id|First visit month|Retention percent|
-----------+-----------------+-----------------+
--        1|       2017-06-01|             15.2|
--        2|       2017-06-01|             15.5|
--        3|       2017-06-01|              6.7|
--        4|       2017-06-01|              7.1|
--        5|       2017-06-01|              4.8|
--Всего строк: 98



--3.2. Monthly Churn (доля активных пользователей, пропустивших следующий месяц)
--
-- Сохраним уникальные пары пользователь–месяц:
-- каждый активный пользователь входит в базу месяца один раз.
--
create view monthly_user_visits as
select distinct f."Source Id", date_trunc('month', v."Start Ts")::date as "Month", v."Uid"
from first_visit_channels as f
join visits_log as v
on f."Uid" = v."Uid"
order by "Month";
--
-- Для мая 2018 возвращаем NULL: нет данных за следующий месяц — июнь.
--
select m."Source Id", m."Month",
case
	when m."Month" + interval '1 month' > (select max ("Start Ts") from visits_log)
	then null
	else round (100.0 * count(distinct m."Uid") filter (where v."Uid" is null) / count (distinct m."Uid"), 1) 
end as "Churn Percent"
from monthly_user_visits as m
left join visits_log as v
on m."Uid" = v."Uid" 
and m."Month" + interval '1 month' = date_trunc('month', v."Start Ts")::date
group by m."Month", m."Source Id";

--Результат:
--Первые строки:
--Source Id|Month     |Churn Percent|
-----------+----------+-------------+
--        1|2017-06-01|         84.8|
--        2|2017-06-01|         84.5|
--        3|2017-06-01|         93.3|
--        4|2017-06-01|         92.9|
--Всего строк: 98


--
-- Часть 4. Покупатели и деньги
--Свяжем посетителей с заказами и сравним стоимость покупателя с его выручкой.
--

--4.1. Новые покупатели и Conversion Rate (конверсия в первую покупку за 30 дней)
--
-- 30 дней отсчитываем от точного времени первого визита.
-- Пользователей без покупок сохраняем в базе расчёта конверсии.
-- Если не у всей группы наблюдаются полные 30 дней, конверсия — NULL.
--
create view new_buyers as
select f."Source Id", date_trunc('month', f."Start Ts")::date as "First visit month", count(distinct o."Uid") as "New buyers",
case
	when max (f."Start Ts") + interval '30 days' > (select max ("Buy Ts") from orders_log)
	then null
	else round (100.0 * count(distinct o."Uid") / count(distinct f."Uid"), 1) 
end as "Conversion percent"
from first_visit_channels as f
left join orders_log as o
on f."Uid" = o."Uid" and o."Buy Ts" <= f."Start Ts" + interval '30 days'
group by f."Source Id", "First visit month"; 

--Результат:
--Первые строки:
--Source Id|First visit month|New buyers|Conversion percent|
-----------+-----------------+----------+------------------+
--        1|       2017-06-01|       197|              31.2|
--        1|       2017-07-01|       151|              28.0|
--        1|       2017-08-01|       105|              28.6|
--        1|       2017-09-01|       217|              31.6|
--        1|       2017-10-01|       321|              31.1|
--        1|       2017-11-01|       296|              26.5|
--Всего строк: 98



--4.2. CAC (стоимость привлечения покупателя)
--
-- Расходы берём за месяц первого визита покупателей.
-- Для неполных 30-дневных окон CAC — NULL: число покупателей может быть занижено.
-- Каналы 6 и 7 не попадают в JOIN: в costs нет данных об их расходах.
-- 
create view CAC as
select n."Source Id", n."First visit month", 
case
	when n."Conversion percent" is null
	then null
	else round (sum(c.costs / n."New buyers"), 1)
end  as "CAC"
from new_buyers as n
join costs as c
on n."Source Id" = c.source_id and n."First visit month" = date_trunc('month', c.dt)
group by n."First visit month", n."Source Id", n."Conversion percent"; 

--Результат:
--Первые строки:
--Source Id|First visit month|CAC |
-----------+-----------------+----+
--        1|       2017-06-01| 5.7|
--        1|       2017-07-01| 7.1|
--        1|       2017-08-01| 9.1|
--        1|       2017-09-01| 6.9|
--Всего строк: 84



--4.3. 30-day LTV (выручка покупателя за 30 дней)
--
-- 30 суток считаем с точного момента первой покупки, включая её.
-- Покупки в момент окончания окна и позже не учитываем.
--
create view LTV_30 as
select o."Uid", f."First order date", sum(
case 
	when f."First order date" <= o."Buy Ts" and  o."Buy Ts" < f."First order date" + interval '30 days'  
	then o."Revenue"
	else 0
end
) as "Revenue"
from orders_log as o
left join (
select distinct on ("Uid") "Buy Ts" as "First order date", "Uid"
from orders_log
order by "Uid", "Buy Ts"
) as f
on o."Uid" = f."Uid"
group by o."Uid", f."First order date";

--Результат:
--Первые строки:
--Uid                 |First order date       |Revenue|
----------------------+-----------------------+-------+
--2359644951638232782 |2017-11-14 16:56:00.000|   1.68|
--11420594199167807176|2017-10-04 21:42:00.000|   0.18|
--12355045482600010505|2017-09-23 13:53:00.000|   1.22|
--7611445451914635477 |2017-11-24 21:18:00.000|   1.33|
--Всего строк: 36,523



--4.4. Юнит-экономика: CAC и LTV рядом по каналам
--
-- Берём тех же покупателей, что и для CAC: первая покупка за 30 дней от первого визита.
-- Выручку и CAC сопоставляем по каналу и месяцу первого визита.
-- Для когорты мая 2018 выручка — NULL: недостаточно данных для 30-дневного наблюдения.
--
select m."Source Id", m."First visit month", m."AVG Revenue", c."CAC"
from (
select f."Source Id", date_trunc('month', f."Start Ts")::date as "First visit month", 
case 
	when date_trunc('month', f."Start Ts")::date < DATE '2018-05-01'
	then round (sum(l."Revenue") / count(l."Uid"), 1) 
	else null
end as "AVG Revenue"
from LTV_30 as l
join first_visit_channels as f
on l."Uid" = f."Uid"
where l."First order date" <= f."Start Ts" + interval '30 days'
group by "First visit month", "Source Id"
) as m
left join CAC as c
on m."Source Id" = c."Source Id" and m."First visit month" = c."First visit month"
order by m."First visit month", m."Source Id";

--Результат:
--Первые строки:
--Source Id|First visit month|AVG Revenue|CAC |
-----------+-----------------+-----------+----+
--        1|       2017-06-01|        7.3| 5.7|
--        2|       2017-06-01|        5.0| 9.8|
--        3|       2017-06-01|        5.0|11.5|
--        4|       2017-06-01|        4.9| 8.1|
--Всего строк: 85


--4.5. Итог по каналам: CAC и выручка на покупателя за период (июнь 2017 – апрель 2018)
--
-- Май исключаем во всех трёх блоках: для майской когорты не хватает наблюдения.
-- Итоговый CAC — общие расходы / общее число покупателей за выбранный период.
-- LTV/CAC считаем по неокруглённым значениям; округляем только вывод.
-- Каналы 6 и 7 выпадают при JOIN: в costs нет данных об их расходах.
--
select a."Source Id", round (a."AVG Revenue", 1) as "AVG Revenue", round (c.costs / n."New buyers", 1) as "CAC", 
round ((a."AVG Revenue")/(c.costs / n."New buyers"), 2) as "LTV to CAC"
from (
select f."Source Id", sum(l."Revenue") / count(l."Uid") as "AVG Revenue"
from LTV_30 as l
join first_visit_channels as f
on l."Uid" = f."Uid"
where l."First order date" <= f."Start Ts" + interval '30 days' and f."Start Ts" < DATE '2018-05-01'
group by "Source Id"
) as a
join (
select source_id, sum(costs) as costs
from costs 
where dt < DATE '2018-05-01'
group by source_id
) as c
on a."Source Id" = c.source_id
join (
select "Source Id", sum("New buyers") as "New buyers"
from new_buyers
where "First visit month" < DATE '2018-05-01'
group by "Source Id"
) as n 
on a."Source Id" = n."Source Id";

--Результат:
--Source Id|AVG Revenue|CAC |LTV to CAC|
-----------+-----------+----+----------+
--        1|        6.0| 7.9|      0.76|
--        2|        7.5|15.5|      0.48|
--        3|        4.7|15.8|      0.30|
--        4|        4.6| 6.8|      0.67|
--        5|        5.1| 8.4|      0.61|
--        9|        3.8| 7.6|      0.51|
--       10|        3.1| 4.9|      0.63|


--4.6. Доля каналов в рекламном бюджете (июнь 2017 – апрель 2018)
--
-- Показывает, какую часть общих расходов получает каждый канал.
-- Период тот же, что в 4.5: май исключаем.
-- Каналы 6 и 7 в таблице нет: в costs нет данных об их расходах.
--
select source_id as "Source Id", round (100.0 * sum(costs) / sum(sum(costs)) over (), 1) as "Budget share"
from costs
where dt < DATE '2018-05-01'
group by source_id
order by "Budget share" desc;

--Результат:
--Source Id|Budget share|
-----------+------------+
--        3|        43.0|
--        4|        18.5|
--        5|        15.7|
--        2|        13.1|
--        1|         6.3|
--       10|         1.8|
--        9|         1.7|

