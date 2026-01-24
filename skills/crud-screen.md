# CRUD Screen Design Skill

Guidelines for designing list/detail/create/edit/delete screens.

Language/framework-agnostic; concept-based.

---

## Screen set

Typical CRUD routes:

- List: `/users` (Read: collection)
- Detail: `/users/:id` (Read: single)
- Create: `/users/new` (Create)
- Edit: `/users/:id/edit` (Update)
- Delete: modal/confirm (Delete)

---

## List screen

Required:

- Table/list: show data
- Pagination: handle large datasets
- Search: filtering
- Create button: navigation to create

Optional:

- Sorting: click column headers
- Filters: status/category, etc
- Bulk actions: multi-select + delete, etc
- Export: CSV/Excel

States:

- Loading: show spinner/skeleton
- Success (has data): show table
- Success (empty): show empty state
- Error: show error + retry

---

## Detail screen

Required:

- Field display
- Edit button
- Delete button (confirm modal)
- Back to list

Layout patterns:

- Card: simple information
- Tabs: large amount of information
- Sections: group related information

---

## Create/Edit screens

Form elements:

- Inputs: text, number, date, etc
- Validation: realtime + on submit
- Save button
- Cancel button

Validation timing:

- On input: format checks
- On blur: required checks
- On submit: re-validate all fields
- Server-side: business rules

Error display:

```
Field-level: show red text under the field
  e.g. "Email format is invalid."

Form-level: show a summary at the top
  e.g. "There are 3 errors in your input."
```

---

## Delete flow

Confirm flow:

1. Click delete
2. Show confirm modal (e.g. "Are you sure?")
3. Cancel: close modal
4. Confirm: call delete API
5. Success: return to list + success message
6. Failure: show error message

Delete types:

- Hard delete: remove from DB (when data is truly disposable)
- Soft delete: mark as deleted (when restore/audit matters)

---

## Common patterns

Loading:

- Initial load: full-page spinner or skeleton
- Partial update: inline spinner
- Submitting: disable button + spinner

Success/error messages:

- Success: toast (auto-dismiss after 3-5s)
- Warning: toast (auto-dismiss or manual)
- Error: toast or inline (usually manual dismiss)

Unsaved changes warning:

1. User attempts to leave while form is dirty
2. Show confirm dialog (e.g. "You have unsaved changes")
3. Stay: continue editing
4. Leave: discard changes

---

## Checklist

List:

- [ ] Loading state
- [ ] Empty state
- [ ] Retry on error
- [ ] Pagination works
- [ ] Search/filter works

Detail:

- [ ] Loading state
- [ ] 404 handling for missing id
- [ ] Edit/delete buttons work

Create/Edit:

- [ ] Validation works
- [ ] Error messages are clear
- [ ] Success message on save
- [ ] Unsaved changes warning
- [ ] Cancel confirmation (when needed)

Delete:

- [ ] Confirm before delete
- [ ] Success message
- [ ] Navigate back to list

---

## Anti-patterns

- Delete without confirmation: high risk -> add confirm modal
- Fetch all records: slow -> add pagination
- Client-only validation: security risk -> validate on server too
- Clearing user input on error: bad UX -> preserve input state

---

## Related

- `skills/api-endpoint.md` - API design
- `skills/error-handling.md` - error handling
- `skills/testing.md` - testing
