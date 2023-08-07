call dm.fill_f101_round_f('2018-01-31')

truncate table dm.dm_f101_round_f

truncate table dm.dm_account_turnover_f 

truncate table dm.lg_messages 

--процедура для наполнения витрины  dm.dm_account_turnover_f за указанный диапазон дат
create procedure dm.loop_(in start_date date, in end_date date) as 
$$
declare current_date_ date := start_date;
begin 
	while current_date_ <= end_date 
	loop
		call dm.fill_account_turnover_f(current_date_);
		current_date_ = current_date_ + interval '1 day';
	end loop;
end;
$$ language plpgsql



call dm.loop_('2018-01-01', '2018-01-31')


-------------------------------------------------------------------------


 
select distinct
	acc_d.account_rk
from ds.md_ledger_account_s s
join ds.md_account_d acc_d
on substr(acc_d.account_number, 1, 5) = to_char(s.ledger_account, 'FM99999999')

select distinct
	datf.account_rk 
from dm.dm_account_turnover_f datf

--создание схемы dm, таблицы логов + seqeunce

-- показать dm.loop +  coalesce в процедуре оборотов где nullif 
-- + запустить через pgAgent


--показать процедуру 101
-- расчет новых полей и total через cte
-- coalesce в процедуре 101 , где все обороты, 
--т.к. на последнем left join образуются null по тем account_rk 
--которых нет первом from + join (112 vs 39)



--------------------версия 2

CREATE OR REPLACE PROCEDURE dm.fill_f101_round_f(IN i_ondate date)
 LANGUAGE plpgsql
AS $procedure$
declare
	v_RowCount int;
begin
    call dm.writelog( '[BEGIN] fill(i_OnDate => date ''' 
         || to_char(i_OnDate, 'yyyy-mm-dd') 
         || ''');', 1
       );
    
    call dm.writelog( 'delete on_date = ' 
         || to_char(i_OnDate, 'yyyy-mm-dd'), 1
       );

    delete
      from dm.DM_F101_ROUND_F f
     where from_date = date_trunc('month', i_OnDate)  
       and to_date = (date_trunc('MONTH', i_OnDate) + INTERVAL '1 MONTH - 1 day');
   
    call dm.writelog('insert', 1);
   
    insert 
      into dm.dm_f101_round_f
           ( from_date         
           , to_date           
           , chapter           
           , ledger_account    
           , characteristic    
           , balance_in_rub    
           , balance_in_val    
           , balance_in_total  
           , turn_deb_rub      
           , turn_deb_val      
           , turn_deb_total    
           , turn_cre_rub      
           , turn_cre_val      
           , turn_cre_total    
           , balance_out_rub  
           , balance_out_val   
           , balance_out_total 
           )
    with cte as (
    select  date_trunc('month', i_OnDate)        as from_date,
           (date_trunc('MONTH', i_OnDate) + INTERVAL '1 MONTH - 1 day')  as to_date,
           s.chapter                             as chapter,
           substr(acc_d.account_number, 1, 5)    as ledger_account,
           acc_d.char_type                       as characteristic,
           -- RUB balance
           sum( case 
                  when cur.currency_code in ('643', '810')
                  then b.balance_out
                  else 0
                 end
              )                                       as balance_in_rub,
          -- VAL balance converted to rub
          sum( case 
                 when cur.currency_code not in ('643', '810')
                 then b.balance_out * exch_r.reduced_cource
                 else 0
                end
             )                                       as balance_in_val,
          -- Total: RUB balance + VAL converted to rub
          sum(  case 
                 when cur.currency_code in ('643', '810')
                 then b.balance_out
                 else b.balance_out * exch_r.reduced_cource
               end
             )                                       as balance_in_total  ,
           -- RUB debet turnover
           coalesce(sum(case 
                 when cur.currency_code in ('643', '810')
                 then at.debet_amount_rub
                 else 0
               end
           ), 0)                                       as turn_deb_rub,
           -- VAL debet turnover converted
           coalesce(sum(case 
                 when cur.currency_code not in ('643', '810')
                 then at.debet_amount_rub
                 else 0
               end
           ), 0)                                       as turn_deb_val,
           -- SUM = RUB debet turnover + VAL debet turnover converted
           coalesce(sum(at.debet_amount_rub), 0)       as turn_deb_total,
           -- RUB credit turnover
           coalesce(sum(case 
                 when cur.currency_code in ('643', '810')
                 then at.credit_amount_rub
                 else 0
               end
              ), 0)                                    as turn_cre_rub,
           -- VAL credit turnover converted
           coalesce(sum(case 
                 when cur.currency_code not in ('643', '810') 
                 then at.credit_amount_rub
                 else 0
               end
              ), 0)                                    as turn_cre_val,
           -- SUM = RUB credit turnover + VAL credit turnover converted
           coalesce(sum(at.credit_amount_rub), 0)      as turn_cre_total,
           -- BALANCE_OUT_RUB 
           coalesce(sum(case
	           	 when acc_d.char_type = 'A' and cur.currency_code in ('643', '810')
	               then b.balance_out - at.credit_amount_rub + at.debet_amount_rub
	             when acc_d.char_type = 'P' and cur.currency_code in ('643', '810')
	               then b.balance_out + at.credit_amount_rub - at.debet_amount_rub
	       	   end
	       	   ), 0)    								as balance_out_rub,
	       -- BALANCE_OUT_VAL
           coalesce(sum(case
	           	 when acc_d.char_type = 'A' and cur.currency_code not in ('643', '810')
	           	   then (b.balance_out * exch_r.reduced_cource) - at.credit_amount_rub + at.debet_amount_rub
	           	 when acc_d.char_type = 'P' and cur.currency_code not in ('643', '810')
	           	   then (b.balance_out * exch_r.reduced_cource) + at.credit_amount_rub - at.debet_amount_rub 
	           end
	           ), 0)                 			         as balance_out_val
      from ds.md_ledger_account_s s
      join ds.md_account_d acc_d
        on substr(acc_d.account_number, 1, 5) = to_char(s.ledger_account, 'FM99999999')
      join ds.md_currency_d cur
        on cur.currency_rk = acc_d.currency_rk
      left 
      join ds.ft_balance_f b
        on b.account_rk = acc_d.account_rk
       and b.on_date  = (date_trunc('month', i_OnDate) - INTERVAL '1 day')
      left 
      join ds.md_exchange_rate_d exch_r
        on exch_r.currency_rk = acc_d.currency_rk
       and i_OnDate between exch_r.data_actual_date and exch_r.data_actual_end_date
      left 
      join dm.dm_account_turnover_f at
        on at.account_rk = acc_d.account_rk
       and at.on_date between date_trunc('month', i_OnDate) and (date_trunc('MONTH', i_OnDate) + INTERVAL '1 MONTH - 1 day')
     where i_OnDate between s.start_date and s.end_date
       and i_OnDate between acc_d.data_actual_date and acc_d.data_actual_end_date
       and i_OnDate between cur.data_actual_date and cur.data_actual_end_date
     group by s.chapter,
           substr(acc_d.account_number, 1, 5),
           acc_d.char_type
     )
     select *, (balance_out_val + balance_out_rub) as balance_out_total  
     from cte;
	
	GET DIAGNOSTICS v_RowCount = ROW_COUNT;
    call dm.writelog('[END] inserted ' ||  to_char(v_RowCount,'FM99999999') || ' rows.', 1);

    commit;
 end;$procedure$
;

