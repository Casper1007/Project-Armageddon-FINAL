# EC2 → RDS Integration Lab - Documentation Index

## 📚 Quick Navigation

### 🚀 START HERE
1. **[DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)** ← Current status and what's been done
2. **[README.md](README.md)** ← Overview and quick start guide

### 🔍 For Verification
3. **[LAB_VERIFICATION_GUIDE.md](LAB_VERIFICATION_GUIDE.md)** ← Detailed verification steps (6.1-6.8)
4. **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** ← AWS CLI commands and one-liners

### 🛠️ For Troubleshooting
5. **Terraform Configuration**: `main.tf` (all infrastructure as code)
6. **Application Source**: `app.py` (Flask application)
7. **Startup Script**: `1a_user_data.sh` (EC2 initialization)

### 📊 Reference Resources
- `terraform.tfstate` - Current infrastructure state
- `verify_lab.sh` - Automated verification script
- `test_app.sh` - Application testing script

---

## 📖 Document Descriptions

### DEPLOYMENT_SUMMARY.md
**Purpose**: High-level overview of what's been completed  
**Contents**:
- Infrastructure status checkmarks
- Current state of all resources
- Security model validation
- Verification checklist
- Troubleshooting quick links

**Read if**: You want to know "what's done and what to do next?"

---

### README.md
**Purpose**: Comprehensive lab overview and getting started guide  
**Contents**:
- Architecture diagram and flow
- What has been deployed
- How to verify everything works
- Testing the complete data flow
- Security model explanation
- File structure
- Resource details

**Read if**: You're new to this lab and want full context

---

### LAB_VERIFICATION_GUIDE.md
**Purpose**: Step-by-step verification matching lab requirements (sections 6.1-6.8)  
**Contents**:
- Section 6.1: Verify EC2 Instance
- Section 6.2: Verify IAM Role
- Section 6.3: Verify RDS Status
- Section 6.4: Verify RDS Endpoint
- Section 6.5: Verify Security Groups (CRITICAL)
- Section 6.6: Verify Secrets Manager
- Section 6.7: Verify Database Connectivity
- Section 6.8: Verify End-to-End Data Flow
- Common failure modes and troubleshooting
- Proof of knowledge statements

**Read if**: You need to verify the lab meets all requirements

---

### QUICK_REFERENCE.md
**Purpose**: Copy-paste AWS CLI commands for common tasks  
**Contents**:
- Get infrastructure details
- All 8 verification commands (6.1-6.8)
- Terraform commands
- Debugging commands
- One-liners for quick checks
- Application endpoints
- Variables reference table

**Read if**: You want to quickly run commands without typing them

---

### main.tf
**Purpose**: Complete Infrastructure as Code definition  
**Contains**:
- VPC, subnets, routing
- Security groups
- EC2 instance
- RDS instance
- IAM roles and policies
- Secrets Manager
- CloudWatch monitoring
- SNS notifications
- Parameter Store configuration

---

### app.py
**Purpose**: Flask application source code  
**Features**:
- Automatic Secrets Manager credential retrieval
- Database connection pooling
- Three main endpoints: /init, /add, /list
- Health check endpoint
- Comprehensive error handling
- Structured logging

---

### 1a_user_data.sh
**Purpose**: EC2 startup script run on first boot  
**Does**:
1. Updates system packages
2. Installs Python and dependencies
3. Installs MySQL client
4. Deploys Flask application
5. Initializes database schema
6. Tests application endpoints
7. Logs everything for debugging

---

## ⏱️ Time-Based Reading Guide

### In 5 Minutes
- Read: DEPLOYMENT_SUMMARY.md
- Understand: What's deployed and current status
- Action: Check verification checklist

### In 15 Minutes
- Read: README.md (sections 1-3)
- Understand: Why this lab matters and architecture overview
- Action: Run first verification commands from QUICK_REFERENCE.md

### In 30 Minutes
- Read: LAB_VERIFICATION_GUIDE.md (6.1-6.4)
- Run: First four verification commands
- Understand: How each component relates

### In 1 Hour
- Read: LAB_VERIFICATION_GUIDE.md (6.5-6.8)
- Read: QUICK_REFERENCE.md troubleshooting section
- Run: Complete verification suite
- Understand: Security model and complete flow

### In 2 Hours
- Fully understand the lab
- Complete all verifications
- Test application endpoints
- Debug any issues
- Ready to submit proof of completion

---

## 🎯 By Role

### If you're the DevOps/SRE person:
1. Start with QUICK_REFERENCE.md
2. Run verify_lab.sh
3. Check main.tf for infrastructure details
4. Monitor logs and metrics

### If you're the Developer:
1. Start with README.md
2. Look at app.py to understand the code
3. Test endpoints using test_app.sh
4. Check application logs in 1a_user_data.sh

### If you're the Security Engineer:
1. Start with LAB_VERIFICATION_GUIDE.md (6.5)
2. Review security groups in main.tf
3. Understand IAM policies in main.tf
4. Check Secrets Manager configuration

### If you're auditing/grading:
1. Read DEPLOYMENT_SUMMARY.md
2. Review LAB_VERIFICATION_GUIDE.md
3. Use QUICK_REFERENCE.md commands to generate proof
4. Check test_app.sh for application functionality

---

## 🔄 Workflow for New Users

```
START
  ↓
Read DEPLOYMENT_SUMMARY.md (5 min)
  ↓
Read README.md (10 min)
  ↓
Run verify_lab.sh (5 min)
  ↓
Read QUICK_REFERENCE.md (10 min)
  ↓
Run manual verification commands (20 min)
  ↓
Read LAB_VERIFICATION_GUIDE.md (15 min)
  ↓
Wait for EC2 startup (2-5 min)
  ↓
Run test_app.sh (5 min)
  ↓
Test application endpoints manually (10 min)
  ↓
COMPLETION
```

---

## 🔍 Finding Specific Information

### "How do I know if RDS is working?"
→ See LAB_VERIFICATION_GUIDE.md section 6.3-6.4

### "What AWS CLI commands do I need?"
→ See QUICK_REFERENCE.md

### "Why isn't the app responding?"
→ See DEPLOYMENT_SUMMARY.md "If Something Isn't Working"

### "What's the security model?"
→ See README.md "🔐 Security Model Explanation"

### "Where are the endpoints?"
→ See README.md "🚀 Testing the Complete Data Flow"

### "How do I SSH into EC2?"
→ See QUICK_REFERENCE.md "Debugging Commands"

### "What are the actual resource IDs?"
→ See DEPLOYMENT_SUMMARY.md "📊 Current State"

### "How do I troubleshoot connectivity?"
→ See LAB_VERIFICATION_GUIDE.md "Common Failure Modes"

### "How do I run the tests?"
→ See DEPLOYMENT_SUMMARY.md "🚀 How to Test"

### "What's the architecture?"
→ See README.md "Architecture (Conceptual)"

---

## ✅ Verification Checklist

After reading documentation, verify:

- [ ] Can explain the architecture (EC2 → RDS via Secrets Manager)
- [ ] Can run AWS CLI verification commands
- [ ] Can find the security group rule that restricts RDS
- [ ] Can explain why RDS has `publicly_accessible = false`
- [ ] Can explain what IAM role does for EC2
- [ ] Can access EC2 via Systems Manager (no SSH key needed)
- [ ] Can retrieve database credentials from Secrets Manager
- [ ] Can connect to RDS MySQL from EC2
- [ ] Can test all three application endpoints
- [ ] Can verify data persists in RDS

---

## 📞 Quick Help Links

| Question | Document | Section |
|----------|----------|---------|
| What's the current status? | DEPLOYMENT_SUMMARY | Top of file |
| How do I test? | README | Section 6 |
| What's the command for X? | QUICK_REFERENCE | Search for keyword |
| Why did X fail? | LAB_VERIFICATION_GUIDE | Common Failure Modes |
| Show me the resource IDs | DEPLOYMENT_SUMMARY | Current State |
| How do I SSH? | QUICK_REFERENCE | Debugging Commands |
| What does the app do? | README | Overview |
| How are credentials managed? | LAB_VERIFICATION_GUIDE | 6.6 |

---

## 🎓 Learning Path

**Beginner** (Haven't seen AWS before):
1. README.md → Understand the pattern
2. DEPLOYMENT_SUMMARY.md → See what's been built
3. QUICK_REFERENCE.md → Run commands to see resources

**Intermediate** (Know AWS basics):
1. LAB_VERIFICATION_GUIDE.md → Work through 6.1-6.8
2. main.tf → Review infrastructure code
3. test_app.sh → Run tests

**Advanced** (AWS professional):
1. main.tf → Review code quality
2. app.py → Code review
3. QUICK_REFERENCE.md → Performance testing
4. Consider stretch goals in README.md

---

## 📊 File Dependencies

```
README.md ────────────────→ DEPLOYMENT_SUMMARY.md
    ↓                              ↓
    │                              └─→ QUICK_REFERENCE.md
    │                                      ↑
    └─→ LAB_VERIFICATION_GUIDE.md ────────┘
            ↓
        Uses commands from QUICK_REFERENCE.md
            ↓
        Validates results from main.tf
            ↓
        Tests app.py via 1a_user_data.sh
```

---

## 🏁 Before You Start

Make sure you have:
- [x] AWS CLI installed and configured
- [x] Appropriate AWS IAM permissions
- [x] jq installed (for JSON parsing)
- [x] curl or wget (for HTTP testing)
- [x] Terraform (if modifying infrastructure)

---

## 📝 Notes for Instructors/Graders

All documents provide:
- ✅ Clear, step-by-step instructions
- ✅ Expected outputs for verification
- ✅ Multiple verification methods (automated + manual)
- ✅ Security best practices highlighted
- ✅ Common failure modes and solutions
- ✅ Proof generation for grading

Students should be able to:
- ✅ Run `verify_lab.sh` successfully
- ✅ Execute all CLI commands from QUICK_REFERENCE.md
- ✅ Retrieve secret from Secrets Manager
- ✅ Test application endpoints
- ✅ Verify data persists in RDS

---

## 📅 Timeline

- **Deployment Time**: ~15 minutes (Terraform apply)
- **EC2 Startup**: ~2-5 minutes (User data script)
- **Test Time**: ~10 minutes (API testing)
- **Verification Time**: ~30 minutes (Complete verification)

**Total**: ~1 hour from deployment to full verification

---

**Document Version**: 1.0  
**Last Updated**: January 20, 2026  
**Status**: Complete and ready for testing
