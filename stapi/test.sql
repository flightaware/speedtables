-- $Id$

create table stapi_test (
	isbn	varchar primary key,
	title	varchar,
	author	varchar,
	pages	integer
);

insert into stapi_test values ('0-13-110933-2','C: A Reference Manual','Harbison and Steele',0);
insert into stapi_test values ('0-201-06196-1','The Design and Implementation of 4.3BSD','Leffler, McKusick, Karels, and Quarterman',0);
insert into stapi_test values ('1-56592-124-0','Building Internet Firewalls','Chapman and Zwicky',0);
insert into stapi_test values ('1-56592-512-2','DNS and BIND','Paul Albitz and Cricket Liu',482);

