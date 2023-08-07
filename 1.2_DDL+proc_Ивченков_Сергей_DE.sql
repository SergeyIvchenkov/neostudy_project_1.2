create schema dm

create table dm.dm_account_turnover_f (
	on_date date,
	account_rk numeric,
	credit_amount numeric(23, 8),
	credit_amount_rub numeric(23, 8),
	debet_amount numeric(23, 8),
	debet_amount_rub numeric(23, 8)
)

create table dm.dm_f101_round_f (
	FROM_DATE date,
	"to_date" date,
	CHAPTER varchar(1),
	LEDGER_ACCOUNT varchar(5),
	CHARACTERISTIC varchar(1),
	BALANCE_IN_RUB numeric(23, 8),
	R_BALANCE_IN_RUB numeric(23, 8),
	BALANCE_IN_VAL numeric(23, 8),
	R_BALANCE_IN_VAL numeric(23, 8),
	BALANCE_IN_TOTAL numeric(23, 8),
	R_BALANCE_IN_TOTAL numeric(23, 8),
	TURN_DEB_RUB numeric(23, 8),
	R_TURN_DEB_RUB numeric(23, 8),
	TURN_DEB_VAL numeric(23, 8),
	R_TURN_DEB_VAL numeric(23, 8),
	TURN_DEB_TOTAL numeric(23, 8),
	R_TURN_DEB_TOTAL numeric(23, 8),
	TURN_CRE_RUB numeric(23, 8),
	R_TURN_CRE_RUB numeric(23, 8),
	TURN_CRE_VAL numeric(23, 8),
	R_TURN_CRE_VAL numeric(23, 8),
	TURN_CRE_TOTAL numeric(23, 8),
	R_TURN_CRE_TOTAL numeric(23, 8),
	BALANCE_OUT_RUB numeric(23, 8),
	R_BALANCE_OUT_RUB numeric(23, 8),
	BALANCE_OUT_VAL numeric(23, 8),
	R_BALANCE_OUT_VAL numeric(23, 8),
	BALANCE_OUT_TOTAL numeric(23, 8),
	R_BALANCE_OUT_TOTAL numeric(23, 8)
)


create or replace procedure dm.fill_account_turnover_f (
   i_OnDate date
)
language plpgsql    
as $$
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
      from dm.dm_account_turnover_f f
     where f.on_date = i_OnDate;
   
    call dm.writelog('insert', 1);
	
    insert
      into dm.dm_account_turnover_f
           ( on_date
           , account_rk
           , credit_amount
           , credit_amount_rub
           , debet_amount
           , debet_amount_rub
           )
    with wt_turn as
    ( select p.credit_account_rk                  as account_rk
           , p.credit_amount                      as credit_amount
           , p.credit_amount * nullif(er.reduced_cource, 1)         as credit_amount_rub
           , cast(null as numeric)                 as debet_amount
           , cast(null as numeric)                 as debet_amount_rub
        from ds.ft_posting_f p
        join ds.md_account_d a
          on a.account_rk = p.credit_account_rk
        left
        join ds.md_exchange_rate_d er
          on er.currency_rk = a.currency_rk
         and i_OnDate between er.data_actual_date   and er.data_actual_end_date
       where p.oper_date = i_OnDate
         and i_OnDate           between a.data_actual_date    and a.data_actual_end_date
         and a.data_actual_date between date_trunc('month', i_OnDate) and (date_trunc('MONTH', i_OnDate) + INTERVAL '1 MONTH - 1 day')
       union all
      select p.debet_account_rk                   as account_rk
           , cast(null as numeric)                 as credit_amount
           , cast(null as numeric)                 as credit_amount_rub
           , p.debet_amount                       as debet_amount
           , p.debet_amount * nullif(er.reduced_cource, 1)          as debet_amount_rub
        from ds.ft_posting_f p
        join ds.md_account_d a
          on a.account_rk = p.debet_account_rk
        left 
        join ds.md_exchange_rate_d er
          on er.currency_rk = a.currency_rk
         and i_OnDate between er.data_actual_date and er.data_actual_end_date
       where p.oper_date = i_OnDate
         and i_OnDate           between a.data_actual_date and a.data_actual_end_date
         and a.data_actual_date between date_trunc('month', i_OnDate) and (date_trunc('MONTH', i_OnDate) + INTERVAL '1 MONTH - 1 day')
    )
    select i_OnDate                               as on_date
         , t.account_rk
         , sum(t.credit_amount)                   as credit_amount
         , sum(t.credit_amount_rub)               as credit_amount_rub
         , sum(t.debet_amount)                    as debet_amount
         , sum(t.debet_amount_rub)                as debet_amount_rub
      from wt_turn t
     group by t.account_rk;
	 
	GET DIAGNOSTICS v_RowCount = ROW_COUNT;
    call dm.writelog('[END] inserted ' || to_char(v_RowCount,'FM99999999') || ' rows.', 1);

    commit;
end;$$

create or replace procedure dm.fill_f101_round_f ( 
  i_OnDate  date
)
language plpgsql    
as $$
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
              )                                  as balance_in_rub,
          -- VAL balance converted to rub
          sum( case 
                 when cur.currency_code not in ('643', '810')
                 then b.balance_out * exch_r.reduced_cource
                 else 0
                end
             )                                   as balance_in_val,
          -- Total: RUB balance + VAL converted to rub
          sum(  case 
                 when cur.currency_code in ('643', '810')
                 then b.balance_out
                 else b.balance_out * exch_r.reduced_cource
               end
             )                                   as balance_in_total  ,
           -- RUB debet turnover
           sum(case 
                 when cur.currency_code in ('643', '810')
                 then at.debet_amount_rub
                 else 0
               end
           )                                     as turn_deb_rub,
           -- VAL debet turnover converted
           sum(case 
                 when cur.currency_code not in ('643', '810')
                 then at.debet_amount_rub
                 else 0
               end
           )                                     as turn_deb_val,
           -- SUM = RUB debet turnover + VAL debet turnover converted
           sum(at.debet_amount_rub)              as turn_deb_total,
           -- RUB credit turnover
           sum(case 
                 when cur.currency_code in ('643', '810')
                 then at.credit_amount_rub
                 else 0
               end
              )                                  as turn_cre_rub,
           -- VAL credit turnover converted
           sum(case 
                 when cur.currency_code not in ('643', '810')
                 then at.credit_amount_rub
                 else 0
               end
              )                                  as turn_cre_val,
           -- SUM = RUB credit turnover + VAL credit turnover converted
           sum(at.credit_amount_rub)             as turn_cre_total,
           cast(null as numeric)                  as balance_out_rub,
           cast(null as numeric)                  as balance_out_val,
           cast(null as numeric)                  as balance_out_total 
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
           acc_d.char_type;
	
	GET DIAGNOSTICS v_RowCount = ROW_COUNT;
    call dm.writelog('[END] inserted ' ||  to_char(v_RowCount,'FM99999999') || ' rows.', 1);

    commit;
    
  end;$$


create or replace procedure dm.writelog (
   i_message		varchar,
   i_messageType	int
)
language plpgsql    
as $$
declare
	log_NOTICE            constant int := 1;
	log_WARNING           constant int := 2;
	log_ERROR             constant int := 3;
	log_DEBUG             constant int := 4;

	c_splitToTable        constant int := 4000;
	c_splitToDbmsOutput   constant int := 900;

	v_logDate           timestamp;
	v_callerType        varchar;
	v_callerOwner       varchar;
	v_caller            varchar;
	v_line              numeric;
	v_message           varchar;
begin
    v_logDate := now();
    -- split to log table
    v_message := i_message;
	i_messageType	:= log_NOTICE;
    while length(v_message) > 0 loop
      insert into dm.lg_messages ( 	
		record_id,
		date_time,
		pid,
		message,
		message_type,
		usename, 
		datname, 
		client_addr, 
		application_name,
		backend_start
    )
	select 	
			nextval('dm.seq_lg_messages'),
			now(),
			pid,
			substr(v_message, 1, c_splitToTable),
			i_messageType,
			usename, 
			datname, 
			client_addr, 
			application_name,
			backend_start
	 from pg_stat_activity
	where pid = pg_backend_pid();
      v_message := substr(v_message, c_splitToTable + 1);
    end loop;

    commit;
end;$$



create table dm.lg_messages (
		record_id int,
		date_time date,
		pid int,
		message text,
		message_type int,
		usename text,
		datname text,
		client_addr inet,
		application_name text,
		backend_start timestamp
)


create sequence dm.seq_lg_messages start 1 increment  by 1
