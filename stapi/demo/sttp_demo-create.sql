-- $Id$

create table sttp_demo (
	isbn	varchar primary key,
	title	varchar,
	author	varchar
);

insert into sttp_demo values ('0-13-110933-2','C: A Reference Manual','Harbison and Steele');
insert into sttp_demo values ('0-201-06196-1','The Design and Implementation of 4.3BSD','Leffler, McKusick, Karels, and Quarterman');
insert into sttp_demo values ('1-56592-124-0','Building Internet Firewalls','Chapman and Zwicky');
