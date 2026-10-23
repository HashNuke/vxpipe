import type { AvailableTool, ToolCatalog } from "./inspectorTypes";

const mcp = (integration: string, tools: [string, string][]): AvailableTool[] => tools.map(([tool, description]) => ({ type: "mcp", integration, tool, description }));

/** Real platform tools; illustrative MCPs provide long lists for scroll testing. */
export const toolCatalogFixture: ToolCatalog = { mcpAvailable: true, tools: [
  { type: "platform", tool: "get_current_time", description: "Get the current date and time in UTC." },
  { type: "platform", tool: "hangup", description: "End the current call immediately." },
  ...mcp("calendar", [
    ["find_slots", "Find available appointment times."],
    ["book_slot", "Book an appointment at an available time."],
    ["cancel_booking", "Cancel an existing appointment."],
    ["get_booking", "Read the details of an appointment."],
    ["list_bookings", "List upcoming appointments for a customer."],
    ["reschedule_booking", "Move an appointment to a different time."],
    ["list_calendars", "List the calendars available to this account."],
    ["get_calendar", "Read a calendar's details and timezone."],
    ["get_business_hours", "Read the business hours for a calendar."],
    ["list_holidays", "List holidays and scheduled closures."],
    ["list_services", "List available appointment services."],
    ["get_service", "Read an appointment service's duration and requirements."],
    ["list_staff", "List staff members who accept appointments."],
    ["get_staff_availability", "Find a staff member's available hours."],
    ["add_attendee", "Add an attendee to an appointment."],
    ["remove_attendee", "Remove an attendee from an appointment."],
    ["send_reminder", "Send an appointment reminder."],
    ["get_booking_history", "Read changes made to an appointment."],
  ]),
  ...mcp("support", [
    ["search_tickets", "Find support tickets by customer or subject."],
    ["create_ticket", "Create a support ticket for follow-up."],
    ["get_ticket", "Read the details of a support ticket."],
    ["add_reply", "Add a reply to a support ticket."],
  ]),
  ...mcp("billing", [["list_invoices", "Find customer invoices."], ["get_invoice", "Read an invoice and payment status."]]),
  ...mcp("contacts", [["search_contacts", "Find a contact by name or email."], ["get_contact", "Read a contact's details."]]),
  ...mcp("crm", [["find_customer", "Find a customer record."], ["add_note", "Add a note to a customer record."]]),
  ...mcp("inventory", [["list_products", "Search available products."], ["check_stock", "Check stock at a location."]]),
  ...mcp("orders", [["get_order", "Read order details."], ["track_shipment", "Check a shipment's progress."]]),
  ...mcp("knowledge", [["search_articles", "Search the knowledge base."], ["get_article", "Read a knowledge-base article."]]),
  ...mcp("notifications", [["send_email", "Send a customer email."], ["send_sms", "Send a customer text message."]]),
  ...mcp("analytics", [["get_report", "Read a saved report."], ["list_reports", "List available reports."]]),
  ...mcp("files", [["search_files", "Search shared files."], ["read_file", "Read a shared document."]]),
  ...mcp("projects", [["list_tasks", "List open project tasks."], ["create_task", "Create a follow-up task."]]),
] };
