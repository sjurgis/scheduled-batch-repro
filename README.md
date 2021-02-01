# DecsOnD Scheduled Batch issue repro

## Setup

Execute below in CLI

```
git clone https://github.com/sjurgis/scheduled-batch-repro
cd scheduled-batch-repro
sfdx force:org:create -s -f ./config/project-scratch-def.json -a batch_repro --nonamespace
sfdx force:package:install --package 04t3o000000t1DZ -w 60 -u batch_repro -r
sfdx force:source:push -u batch_repro
sfdx force:org:open -p /lightning/cmp/DecsOnD__NewPolicy_SelectTemplate -u batch_repro
```

Once page fully renders, wait few minutes and then execute anonymous:
```apex
DecsOnD.PolicyManager.installTemplate(new DecsOnD.DecisionPointDescriptor('Lead', 'Assignment'), 'Assignment');
```

## Case 1

Then execute anonymous
```apex
DecsOnD.PolicyInvocationContext invocationContext = new DecsOnD.PolicyInvocationContext(
        Lead.SObjectType, 'Assignment'
);
List<Schema.ChildRelationship> childList = My_Custom_Object__c.SObjectType.getDescribe().getChildRelationships();
for (Schema.ChildRelationship child : childList) {
    SObjectType childSobject = child.getChildSObject();
    String sObjectName = childSobject.getDescribe().getName();
    if (sObjectName == 'My_Custom_Object__Feed') {
        System.scheduleBatch(new ScheduledBatchRepro(childSobject), 'never executes', 1);
    }
}
```

Then execute below:

```
sfdx force:data:soql:query -q "SELECT TimesTriggered, CronJobDetail.Name, CronJobDetail.JobType, StartTime,  State FROM CronTrigger WHERE CronJobDetailId IN (SELECT Id FROM CronJobDetail WHERE JobType = '7' AND Name = 'never executes')"
```

Observe job created:
```
TIMESTRIGGERED  CRONJOBDETAIL.NAME  CRONJOBDETAIL.JOBTYPE  STARTTIME                     STATE
──────────────  ──────────────────  ─────────────────────  ────────────────────────────  ───────
                never executes      7                      2021-02-01T22:19:33.000+0000  WAITING
```


Wait few minutes, then execute query again

```
sfdx force:data:soql:query -q "SELECT TimesTriggered, CronJobDetail.Name, CronJobDetail.JobType, StartTime,  State FROM CronTrigger WHERE CronJobDetailId IN (SELECT Id FROM CronJobDetail WHERE JobType = '7' AND Name = 'never executes')"
```

Note that job state went into deleted...

```
TIMESTRIGGERED  CRONJOBDETAIL.NAME  CRONJOBDETAIL.JOBTYPE  STARTTIME                     STATE
──────────────  ──────────────────  ─────────────────────  ────────────────────────────  ───────
1               never executes      7                      2021-02-01T22:19:33.000+0000  DELETED
```

## Case 2
However, if we run below, the job executes fine

```apex
DecsOnD.PolicyInvocationContext invocationContext = new DecsOnD.PolicyInvocationContext(
        Lead.SObjectType, 'Assignment'
);
List<Schema.ChildRelationship> childList = My_Custom_Object__c.SObjectType.getDescribe().getChildRelationships();
for (Schema.ChildRelationship child : childList) {
    SObjectType childSobject = child.getChildSObject();
    String sObjectName = childSobject.getDescribe().getName();
    if (sObjectName == 'My_Custom_Object__Share') {
        System.scheduleBatch(new ScheduledBatchRepro(childSobject), 'executes fine', 1);
    }
}

```


Then execute below:

```
sfdx force:data:soql:query -q "SELECT TimesTriggered, CronJobDetail.Name, CronJobDetail.JobType, StartTime,  State FROM CronTrigger WHERE CronJobDetailId IN (SELECT Id FROM CronJobDetail WHERE JobType = '7' AND Name = 'executes fine')"
```

Observe job created:
```
TIMESTRIGGERED  CRONJOBDETAIL.NAME  CRONJOBDETAIL.JOBTYPE  STARTTIME                     STATE
──────────────  ──────────────────  ─────────────────────  ────────────────────────────  ───────
                executes fine       7                      2021-02-01T22:23:20.000+0000  WAITING
```


Wait few minutes, then execute query again

```
sfdx force:data:soql:query -q "SELECT TimesTriggered, CronJobDetail.Name, CronJobDetail.JobType, StartTime,  State FROM CronTrigger WHERE CronJobDetailId IN (SELECT Id FROM CronJobDetail WHERE JobType = '7' AND Name = 'executes fine')"
```

Which returns no results because it executed as batch
```
Your query returned no results.
```

Which can be confirmed by running query below
```
sfdx force:data:soql:query -q "SELECT Status, CompletedDate FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name ='ScheduledBatchRepro'"
```

```
STATUS     COMPLETEDDATE
─────────  ────────────────────────────
Completed  2021-02-01T22:17:17.000+0000
```

## Case 3
And if we run below, the job does not get created at all (because My_Custom_Object__Feed wasn't created).

```apex
List<Schema.ChildRelationship> childList = My_Custom_Object__c.SObjectType.getDescribe().getChildRelationships();
for (Schema.ChildRelationship child : childList) {
    SObjectType childSobject = child.getChildSObject();
    String sObjectName = childSobject.getDescribe().getName();
    if (sObjectName == 'My_Custom_Object__Feed') {
        System.scheduleBatch(new ScheduledBatchRepro(childSobject), 'never created', 1);
    }
}
```
Then execute

```
sfdx force:data:soql:query -q "SELECT TimesTriggered, CronJobDetail.Name, CronJobDetail.JobType, StartTime,  State FROM CronTrigger WHERE CronJobDetailId IN (SELECT Id FROM CronJobDetail WHERE JobType = '7' AND Name = 'never created')"
```

Which returns no results because as the type `My_Custom_Object__Feed` does not exist and job did not create
```
Your query returned no results.
```


## Conclusion

IMO there's a couple of potential bugs here:
1. scheduleBatch fails quietly without reporting error to user/admin
2. scheduleBatch fails when there's transient type on it's state (perhaps when it executes it encounters GACK because type is missing)
3. transient type gets created, and we have no way to understand why or how
