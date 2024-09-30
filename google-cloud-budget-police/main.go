package sandboxbillingmgmt

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/rs/zerolog/log"
	"google.golang.org/api/billingbudgets/v1"
	"google.golang.org/api/cloudbilling/v1"
	"google.golang.org/api/cloudresourcemanager/v1"
)

func init() {
	// Register CloudEvents function
	// "ProcessBudgetNotification" will be the entrypoint function
	functions.CloudEvent("ProcessBudgetNotification", processBudgetNotification)
}

const (
	// Indicating that incoming event originates from Cloud Scheduler job
	cloudSchedulerSource = "cloud-scheduler"
)

// processBudgetNotification receives a message and acts accordingly
func processBudgetNotification(ctx context.Context, e event.Event) error {
	log.Info().Msg(fmt.Sprintf("Received event %v", e))

	var notification CloudEventsPubSub
	if err := e.DataAs(&notification); err != nil {
		return fmt.Errorf("error while parsing received message: %w", err)
	}

	// Decode message data
	var notificationData CloudEventsPubSubMsgData
	err := json.Unmarshal(notification.Msg.Data, &notificationData)
	if err != nil {
		return fmt.Errorf("error while decoding message data: %w", err)
	}

	// If incoming event is from Cloud Scheduler, run reassignment procedure for all sandbox projects
	if notificationData.Source == cloudSchedulerSource {
		return reassignBillingAccount(ctx, notification, notificationData)
	}

	// Else run disable billing procedure for a single sandbox project
	return disableBilling(ctx, notification, notificationData)
}

// Checks if billing needs to be disabled and execute if necessary
func disableBilling(ctx context.Context, notification CloudEventsPubSub, notificationData CloudEventsPubSubMsgData) error {
	// Find sandbox project associated with budget notification
	budgetsService, err := billingbudgets.NewService(ctx)
	if err != nil {
		return fmt.Errorf("error while creating billing budget service: %w", err)
	}

	// Abort if input variables are missing
	if notification.Msg.Attributes.BillingAccountID == "" || notification.Msg.Attributes.BudgetID == "" {
		return errors.New("required input variables billing account and/or budget ID are missing")
	}

	budgetName := fmt.Sprintf("billingAccounts/%s/budgets/%s", notification.Msg.Attributes.BillingAccountID, notification.Msg.Attributes.BudgetID)
	budgetResp, err := budgetsService.BillingAccounts.Budgets.Get(budgetName).Do()
	if err != nil {
		return fmt.Errorf("error while getting billing budget %s service: %w", budgetName, err)
	}

	if len(budgetResp.BudgetFilter.Projects) > 1 {
		return fmt.Errorf("more than one project is assigned to budget %s, cannot decide which of them hit the threshold", budgetName)
	}

	projectId := budgetResp.BudgetFilter.Projects[0]

	// Check if costs exceed threshold
	log.Info().Msg(fmt.Sprintf("Comparing costs and budget for project %s", projectId))

	if notificationData.CostAmount < notificationData.BudgetAmount {
		log.Info().Msg(fmt.Sprintf("No action needed, currently %.2f percent of budget is used for project %s", (notificationData.CostAmount * 100 / notificationData.BudgetAmount), projectId))
		return nil
	}

	log.Info().Msg(fmt.Sprintf("Project %s has exceeded cost threshold, currently using %.2f percent of budget", projectId, (notificationData.CostAmount * 100 / notificationData.BudgetAmount)))

	// Disable billing (if not disabled already)
	billingService, err := cloudbilling.NewService(ctx)
	if err != nil {
		return fmt.Errorf("error while creating GCP billing service: %w", err)
	}

	billingInfoResp, err := billingService.Projects.GetBillingInfo(projectId).Do()
	if err != nil {
		return fmt.Errorf("error while getting billing info for project %s: %w", projectId, err)
	}

	if billingInfoResp.BillingAccountName != "" || billingInfoResp.BillingEnabled {
		// Set account to empty, represents disabling billing
		updatedBillingInfo := &cloudbilling.ProjectBillingInfo{
			BillingAccountName: "",
		}

		_, err = billingService.Projects.UpdateBillingInfo(projectId, updatedBillingInfo).Do()
		if err != nil {
			return fmt.Errorf("error while updating billing info for project %s: %w", projectId, err)
		}

		log.Info().Msg(fmt.Sprintf("Successfully disabled billing for project %s", projectId))
	} else {
		log.Info().Msg(fmt.Sprintf("Billing for project %s is already disabled", projectId))
	}

	return nil
}

func reassignBillingAccount(ctx context.Context, notification CloudEventsPubSub, notificationData CloudEventsPubSubMsgData) error {
	// Iterate over all sandbox projects
	cloudresourcemanagerService, err := cloudresourcemanager.NewService(ctx)
	if err != nil {
		return fmt.Errorf("error while creating GCP Cloud Resource Manager service: %w", err)
	}

	filter := fmt.Sprintf("parent.type:folder AND parent.id=%s", notificationData.SandboxFolderID)
	projResp, err := cloudresourcemanagerService.Projects.List().Filter(filter).Do()
	if err != nil {
		return fmt.Errorf("error while listing all GCP sandbox projects: %w", err)
	}

	// Check and update billing (if necessary) for all sandbox projects
	billingService, err := cloudbilling.NewService(ctx)
	if err != nil {
		return fmt.Errorf("error while creating GCP billing service: %w", err)
	}

	for _, p := range projResp.Projects {
		billingInfoResp, err := billingService.Projects.GetBillingInfo(fmt.Sprintf("projects/%s", p.ProjectId)).Do()
		if err != nil {
			return fmt.Errorf("error while getting billing info for project %s: %w", p.ProjectId, err)
		}

		if billingInfoResp.BillingAccountName == "" || !billingInfoResp.BillingEnabled {
			// Enable billing again
			updatedBillingInfo := &cloudbilling.ProjectBillingInfo{
				BillingAccountName: fmt.Sprintf("billingAccounts/%s", notification.Msg.Attributes.BillingAccountID),
			}

			_, err = billingService.Projects.UpdateBillingInfo(fmt.Sprintf("projects/%s", p.ProjectId), updatedBillingInfo).Do()
			if err != nil {
				return fmt.Errorf("error while updating billing info for project %s: %w", p.ProjectId, err)
			}

			log.Info().Msg(fmt.Sprintf("Successfully reenabled billing for project %s", p.ProjectId))
		} else {
			log.Info().Msg(fmt.Sprintf("No action needed, billing is already enabled for project %s", p.ProjectId))
		}
	}

	return nil
}
