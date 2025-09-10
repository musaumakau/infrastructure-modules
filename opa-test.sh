#!/bin/bash

# Manual governance policy check script
# Run this locally to debug governance issues

echo "🔍 Debugging Governance Policy Violations..."

# 1. Check what policy tool is being used
echo "=== Policy Tool Detection ==="
if command -v conftest &> /dev/null; then
    echo "✅ Conftest found"
    conftest verify --help | head -10
elif command -v opa &> /dev/null; then
    echo "✅ OPA found"
    opa --help | head -10
elif command -v checkov &> /dev/null; then
    echo "✅ Checkov found"
    checkov --help | head -10
else
    echo "❌ No known policy tools found"
fi

# 2. Find policy files
echo -e "\n=== Policy Files ==="
find . -name "*.rego" -o -name "*policy*" -o -name "*governance*" | head -10

# 3. Check for common governance issues
echo -e "\n=== Resource Analysis ==="
echo "Launch templates found:"
grep -r "aws_launch_template" . --include="*.tf" | wc -l

echo "Required tags check:"
grep -r "CostCenter\|Owner\|Environment" . --include="*.tf" | wc -l

echo "Security groups check:"
grep -r "aws_security_group" . --include="*.tf" | wc -l

echo "KMS encryption check:"
grep -r "encrypted.*=.*true\|kms_key" . --include="*.tf" | wc -l

# 4. Run different policy tools with verbose output
echo -e "\n=== Policy Check Attempts ==="

# Try Conftest
if command -v conftest &> /dev/null; then
    echo "--- Conftest Check ---"
    conftest verify --policy ./policies . --output table --trace || true
fi

# Try OPA
if command -v opa &> /dev/null; then
    echo "--- OPA Check ---"
    opa test --verbose . || true
fi

# Try Checkov with governance focus
if command -v checkov &> /dev/null; then
    echo "--- Checkov Governance Check ---"
    checkov -d . --framework terraform --check CKV2_* --compact || true
fi

# 5. Show terraform resources summary
echo -e "\n=== Terraform Resources Summary ==="
grep -h "^resource " *.tf 2>/dev/null | sort | uniq -c || echo "No .tf files in current directory"

echo -e "\n🏁 Debug complete. Check output above for specific policy violations."
