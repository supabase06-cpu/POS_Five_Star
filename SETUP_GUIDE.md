# Five Star Chicken POS - Setup Guide

## 🚀 Complete Authentication & Authorization System

Your POS system now includes comprehensive user management with:

### ✅ Authentication Features
- **Email/Password Login** with validation
- **Remember Me** functionality (secure storage)
- **Show/Hide Password** toggle
- **Loading states** and error handling
- **Auto-logout** for inactive/expired accounts

### ✅ Authorization & Business Logic
- **User Role Management** (Cashier, Manager, Admin, Owner)
- **Permission-based Access Control**
- **Organization Subscription Checking**
- **Account Status Validation**
- **Real-time Permission Display**

### ✅ Organization Management
- **Subscription Status Tracking**
- **User Limits Enforcement**
- **Feature Access Control**
- **Expiry Date Monitoring**

## 📋 Setup Instructions

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Setup Supabase Database
1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Copy and paste the contents of `supabase_schema.sql`
4. Run the SQL to create all tables and policies

### 3. Create Your First Admin User
1. In Supabase Dashboard → **Authentication** → **Users**
2. Click **"Add User"**
3. Enter admin email and password
4. After user is created, note the **User ID**
5. Go to **SQL Editor** and run:

```sql
-- Replace 'your-user-uuid-here' with actual user ID from step 4
-- Replace organization ID with your organization's ID
UPDATE user_profiles 
SET 
    organization_id = (SELECT id FROM organizations WHERE name = 'Five Star Chicken Main'),
    role = 'admin',
    permissions = '["pos_access", "process_payments", "view_reports", "manage_inventory", "manage_users", "all"]'
WHERE id = 'your-user-uuid-here';
```

### 4. Run the App
```bash
flutter run
```

## 🔐 User Roles & Permissions

### **Cashier** (Default)
- ✅ POS Access
- ❌ Process Payments (needs explicit permission)
- ❌ View Reports
- ❌ Manage Inventory
- ❌ Manage Users

### **Manager**
- ✅ POS Access
- ✅ Process Payments
- ✅ View Reports
- ✅ Manage Inventory
- ❌ Manage Users

### **Admin**
- ✅ All Permissions
- ✅ Manage Users
- ✅ Organization Settings

### **Owner**
- ✅ All Permissions
- ✅ Full Organization Control

## 🏢 Organization Features by Plan

### **Free Plan**
- 1 User
- Basic POS Access
- Limited Features

### **Basic Plan**
- 5 Users
- POS Access
- Basic Reporting

### **Premium Plan**
- 10+ Users
- Full POS Features
- Advanced Reporting
- Inventory Management
- User Management

### **Enterprise Plan**
- Unlimited Users
- All Features
- Custom Integrations
- Priority Support

## 🔧 Login Flow Security Checks

When a user logs in, the system automatically checks:

1. **Valid Credentials** - Email/password verification
2. **Account Status** - User must be active
3. **Organization Status** - Organization must be active
4. **Subscription Status** - Must have valid subscription
5. **POS Permission** - User must have POS access
6. **Role Verification** - Loads user role and permissions

If any check fails, login is rejected with specific error message.

## 📱 Dashboard Features

After successful login, users see:

- **Welcome Section** - Name, role, last login
- **Organization Status** - Subscription info, user count, expiry
- **Permission Overview** - What they can/cannot do
- **Quick Actions** - Role-based action buttons

## 🛠️ Customization

### Adding New Permissions
1. Update `user_model.dart` with new permission methods
2. Add permission checks in `auth_provider.dart`
3. Update UI to show/hide features based on permissions

### Adding New Roles
1. Update database enum in `supabase_schema.sql`
2. Add role logic in `user_model.dart`
3. Update permission assignments

### Organization Features
1. Add new features to `organizations.features` JSON array
2. Update `OrganizationInfo.hasFeature()` method
3. Check features in UI components

## 🚨 Security Notes

- All database access uses Row Level Security (RLS)
- Users can only see their organization's data
- Passwords are securely stored using Flutter Secure Storage
- Session management handled by Supabase Auth
- Real-time permission checking prevents unauthorized access

## 📞 Support

Your POS system is now enterprise-ready with:
- Multi-tenant organization support
- Role-based access control
- Subscription management
- Secure authentication
- Professional UI/UX

Ready for production use! 🎉