set nocount on;

/*CREATE LOGIN*/
select
name,
'1login', 
'CREATE LOGIN [' + name + 
'] WITH PASSWORD='+CONVERT(varchar(max), LOGINPROPERTY(name, 'PasswordHash'),1 )+' HASHED,' +
'DEFAULT_DATABASE=['+default_database_name+'], ' +
'DEFAULT_LANGUAGE=['+default_language_name+']; ' +
CASE WHEN is_disabled=1 THEN ' ALTER LOGIN ['+name+'] DISABLED; ' ELSE '' end
FROM sys.server_principals pr
WHERE type = 'S' and name not like '#%'
UNION ALL
select 
name,
'1login',
'CREATE LOGIN [' + name + '] FROM WINDOWS; ' +
CASE WHEN is_disabled=1 THEN ' ALTER LOGIN ['+name+'] DISABLED; ' ELSE '' end
FROM sys.server_principals pr
WHERE type = 'U' and name not like '#%';

/*INSTANCE LEVEL ROLES*/
SELECT 
member.name,
'2role',
'EXEC sp_addsrvrolemember ''' + member.name + ''',''' + role.name + '''; '
FROM sys.server_role_members
JOIN sys.server_principals AS role
    ON sys.server_role_members.role_principal_id = role.principal_id
JOIN sys.server_principals AS member
    ON sys.server_role_members.member_principal_id = member.principal_id;

/*INSTANCE LEVEL PERMISSIONS*/
SELECT
name, 
'3priv',
'GRANT '+ permission_name +' TO ['+ name COLLATE Latin1_General_CI_AI +']; '
FROM sys.server_permissions pe
INNER JOIN sys.server_principals pr
ON pe.grantee_principal_id = pr.principal_id
WHERE pr.type in ('U','S') and name not like '#%' and permission_name <> 'CONNECT SQL';

/*DB LEVEL PERMISSIONS*/
EXEC sp_MSForEachDB 'IF ''?''  NOT IN (''tempDB'',''model'',''msdb'')
BEGIN
use [?];
select
USER_NAME(p.grantee_principal_id) name,
''4dbpriv-?-''+p.permission_name,
CASE WHEN p.permission_name=''CONNECT'' then ''USE [?]; CREATE USER ['' + USER_NAME(p.grantee_principal_id)+'']; ''
WHEN p.class_desc=''DATABASE'' then p.state_desc+'' ''+p.permission_name+'' TO [''+USER_NAME(p.grantee_principal_id)+'']; ''
ELSE p.state_desc+'' ''+p.permission_name+'' ON ''+OBJECT_NAME(p.major_id)+'' TO [''+USER_NAME(p.grantee_principal_id)+'']; ''
END
from sys.database_permissions p
inner JOIN sys.database_principals dp
on p.grantee_principal_id = dp.principal_id
where
dp.type_desc=''SQL_USER'' and p.grantee_principal_id <> 1 and USER_NAME(p.grantee_principal_id) not like ''#%'';
END';

/*DB LEVEL ROLES*/
EXEC sp_MSForEachDB 'IF ''?''  NOT IN (''tempDB'',''model'',''msdb'')
BEGIN
Use [?]; select USER_NAME(memberuid),''5dbrole-?'',''USE [?]; EXEC sp_addrolemember ''''''+USER_NAME(groupuid)+'''''',''''''+USER_NAME(memberuid)+''''''; '' FROM sys.sysmembers where memberuid <> 1 and USER_NAME(memberuid) not like ''#%'';
END';

