# Terraform State Lock Management

## Overview

Terraform uses state locking to prevent concurrent operations from corrupting the state file. When a Terraform operation (plan, apply, destroy) is running, it acquires a lock on the state file. If another operation tries to access the state while it's locked, it will fail with an error.

## Understanding State Locks

### What is a State Lock?

A state lock is a mechanism that ensures only one Terraform operation can modify the state at a time. Locks are stored in DynamoDB (for AWS S3 backends) and contain metadata about:

- **Lock ID**: A unique identifier for the lock (UUID format)
- **Who**: The user and machine that acquired the lock
- **Created**: Timestamp when the lock was created
- **Operation**: The type of operation (Plan, Apply, Destroy)
- **Path**: The S3 path to the state file
- **Version**: The Terraform version that created the lock

### When Do Locks Occur?

Locks are created automatically when:
- Running `terraform plan`
- Running `terraform apply`
- Running `terraform destroy`
- Any operation that reads or modifies state

### Why Do Locks Persist?

Locks should automatically release when an operation completes, but they can persist if:

1. **Process interruption**: Ctrl+C, terminal closure, or network issues
2. **CI/CD failures**: Pipeline crashes or timeouts
3. **System crashes**: Machine or container shutdown during operation
4. **Network issues**: Connection lost to state backend

## Handling State Locks

### Option 1: Automatic Detection (Recommended)

The `deploy.sh` script automatically detects and offers to clear state locks:

```bash
./deploy.sh
```

When a lock is detected, you'll see:

```
[WARN] Found state lock:
[WARN]   ID: e550de88-751a-3bda-ebf3-b9af189935af
[WARN]   Created: 2025-11-28 08:06:33
[WARN]   By: runner@runnervmg1sw1

Automatically unlock? [yes/NO]:
```

Type `yes` to automatically unlock and continue.

### Option 2: Using the Unlock Script

Use the dedicated unlock script for manual lock management:

```bash
cd infra/terraform
./unlock-state.sh
```

The script will:
1. Detect if a lock exists
2. Display lock details
3. Prompt you to unlock

#### Unlock with Known Lock ID

If you already know the lock ID:

```bash
./unlock-state.sh e550de88-751a-3bda-ebf3-b9af189935af
```

### Option 3: Manual Unlock

If the scripts fail, you can manually force-unlock:

```bash
cd infra/terraform
terraform force-unlock -force <LOCK_ID>
```

Example:
```bash
terraform force-unlock -force e550de88-751a-3bda-ebf3-b9af189935af
```

## Troubleshooting

### Problem: "Could not parse lock ID from Terraform output"

**Cause**: The parsing logic couldn't extract the lock ID from Terraform's output.

**Solution**:
1. Look at the raw Terraform output displayed in the error
2. Find the "Lock Info:" section
3. Copy the ID value (UUID format)
4. Run: `terraform force-unlock -force <LOCK_ID>`

### Problem: "Lock ID does not match existing lock"

**Cause**: You're trying to unlock with the wrong lock ID. This can happen if:
- ANSI color codes interfered with parsing (now fixed)
- Multiple people are working on the same state
- A new lock was created after you detected the old one

**Solution**:
1. Get the current lock ID by running `terraform plan` and checking the error
2. Look for the "Lock Info:" section in the output
3. Use the correct lock ID shown in that section

### Problem: Lock owned by CI/CD pipeline

**Cause**: A CI/CD job is still running or crashed without releasing the lock.

**Solution**:
1. Check if the CI/CD job is still running
2. If running, wait for it to complete or cancel it first
3. If cancelled or crashed, use the unlock scripts to force-unlock
4. Never unlock while a legitimate operation is in progress

### Problem: Repeated lock issues

**Cause**: Multiple team members or CI/CD pipelines running simultaneously.

**Solution**:
- Coordinate with team to ensure only one person deploys at a time
- Configure CI/CD to queue deployments instead of running in parallel
- Use Terraform Cloud/Enterprise for better concurrency handling
- Consider workspace separation for team members

## Best Practices

### 1. Wait Before Force-Unlocking

Always verify that no legitimate operation is running:
- Check with team members
- Verify CI/CD pipelines are not active
- Wait a few minutes to see if the lock clears naturally

### 2. Note the Lock Owner

Before unlocking, check the "Who" field:
```
Who: runner@runnervmg1sw1
```

If it's a CI/CD runner, verify the pipeline is not active.
If it's another team member, communicate before unlocking.

### 3. Use Lock Timeouts

When running Terraform commands, use lock timeouts:
```bash
terraform plan -lock-timeout=10s
```

This makes Terraform wait for a lock to clear instead of failing immediately.

### 4. Avoid Concurrent Operations

Never run multiple Terraform operations simultaneously:
- Don't run `terraform apply` while another apply is in progress
- Don't deploy from multiple terminals or machines
- Configure CI/CD to serialize deployments

### 5. Handle Interruptions Properly

If you need to interrupt a Terraform operation:
1. Let it finish if possible
2. If you must interrupt, use Ctrl+C once and wait
3. Check for locks afterward and clear them if needed

## Lock Information Reference

When you see lock information, here's what each field means:

```
Lock Info:
  ID:        e550de88-751a-3bda-ebf3-b9af189935af  # Unique lock identifier
  Path:      todo-terraform-state-bucket-12345/... # S3 path to state file
  Operation: OperationTypePlan                     # What operation created lock
  Who:       runner@runnervmg1sw1                  # User and machine
  Version:   1.5.0                                 # Terraform version
  Created:   2025-11-28 08:06:33 +0000 UTC        # When lock was created
  Info:                                            # Additional context (usually empty)
```

## Emergency Procedures

### If All Else Fails

If scripts and manual unlock fail:

1. **Check DynamoDB directly**:
   ```bash
   aws dynamodb scan --table-name todo-terraform-lock-table
   ```

2. **Delete the lock from DynamoDB**:
   ```bash
   aws dynamodb delete-item \
     --table-name todo-terraform-lock-table \
     --key '{"LockID":{"S":"todo-terraform-state-bucket-12345/todo-app/terraform.tfstate-md5"}}'
   ```

3. **As a last resort, recreate the state backend**:
   - Back up your state file from S3
   - Delete and recreate the DynamoDB table
   - Reinitialize Terraform

## Getting Help

If you continue to have issues:

1. Check Terraform version compatibility: `terraform version`
2. Verify AWS credentials: `aws sts get-caller-identity`
3. Check DynamoDB table exists: `aws dynamodb describe-table --table-name todo-terraform-lock-table`
4. Review S3 bucket permissions
5. Check network connectivity to AWS

## Related Files

- `deploy.sh`: Main deployment script with automatic lock detection
- `unlock-state.sh`: Dedicated script for managing state locks
- `backend.tf`: Terraform backend configuration
- `.env`: Environment variables (ensure AWS credentials are set)
