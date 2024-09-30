package sandboxbillingmgmt

// CloudEventsBudgetNotification represents the Cloud Event associated with a Pub/Sub message
// published by either an automatic budget notification or the Cloud Scheduler job triggering the reassignment of the billing account
// https://cloud.google.com/eventarc/docs/cloudevents#pubsub
type CloudEventsPubSub struct {
	Msg CloudEventsPubSubMsg `json:"message"`
}

// CloudEventsPubSubMsg is the payload of a Pub/Sub Cloud Event, which is always a standard Pub/Sub message
// https://cloud.google.com/pubsub/docs/reference/rest/v1/PubsubMessage
type CloudEventsPubSubMsg struct {
	Attributes CloudEventsPubSubMsgAttributes `json:"attributes"`
	Data       []byte                         `json:"data"`
}

// CloudEventsPubSubMsgAttributes represents the "attributes" part of a Pub/Sub message
// This can either contain the attributes of an automatic billing notification
// https://cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications#notification_format
// or the custom message sent by the Cloud Scheduler job
type CloudEventsPubSubMsgAttributes struct {
	BillingAccountID string `json:"billingAccountId"`
	BudgetID         string `json:"budgetId"`
}

// CloudEventsPubSubMsgData represents the "data" part of a Pub/Sub message
// This can either contain the attributes of an automatic billing notification
// https://cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications#notification_format
// or the custom message sent by the Cloud Scheduler job
type CloudEventsPubSubMsgData struct {
	// Data fields of automatic billing notification
	BudgetAmount float32 `json:"budgetAmount"`
	CostAmount   float32 `json:"costAmount"`

	// Data fields for custom Cloud Scheduler job message
	Source          string `json:"source"`
	SandboxFolderID string `json:"sandboxFolderId"`
}
