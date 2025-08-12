# Firestore Data Import Lab

This lab guides you through creating a Firestore database, generating test data, and importing it into Firestore using Node.js scripts.

**Lab Link:**  
https://www.cloudskillsboost.google/games/6415/labs/40383

---

## Steps to Complete the Lab

```bash
gcloud config set project $DEVSHELL_PROJECT_ID

gcloud firestore databases create --location=nam5

git clone https://github.com/rosera/pet-theory

cd pet-theory/lab01

npm install @google-cloud/firestore

npm install @google-cloud/logging

curl https://raw.githubusercontent.com/gcpsolution99/GCP-solution/refs/heads/main/Importing%20Data%20to%20a%20Firestore%20Database/importTestData.js > importTestData.js

npm install faker@5.5.3

curl https://raw.githubusercontent.com/gcpsolution99/GCP-solution/refs/heads/main/Importing%20Data%20to%20a%20Firestore%20Database/createTestData.js > createTestData.js

node createTestData 1000

node importTestData customers_1000.csv

npm install csv-parse

node createTestData 20000

node importTestData customers_20000.csv
```

Lab Completion
🎉 Lab completed successfully!
Thank you for completing this Firestore data import lab.
---
Support & Subscription
If you found this lab useful, please subscribe to CloudCupcake for more Google Cloud tutorials and labs!
---
Disclaimer
This lab is intended for educational purposes only. Always ensure you follow your organization's security policies and guidelines when working with cloud resources and data.
---

