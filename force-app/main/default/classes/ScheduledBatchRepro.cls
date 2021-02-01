public class ScheduledBatchRepro implements Database.Batchable<SObject> {
    SObjectType child;
    public ScheduledBatchRepro(SObjectType sob) {
        this.child = sob;
    }
    public virtual Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator('select id from My_Custom_Object__c');
    }
    public virtual void execute(Database.BatchableContext BC, List<SObject> scope) {
    }
    public virtual void finish(Database.BatchableContext BC) {
    }
}
