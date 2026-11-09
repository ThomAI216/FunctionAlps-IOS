## AI-assisted analysis

FunctionAlps runs on AI. Your meal photographs and logs are analysed automatically to produce your food scores, your patterns and your reports, and the same is true of the assessment on our website. Because every core feature depends on it, the health-data consent covers it, and because you cannot have the service without it, you deserve a straight account of what it does, where it runs, and where it falls short.

### 1. What the AI does

- Identifies foods from a photograph or a description, estimates portions, and derives macronutrients and micronutrients.
- Converts voice input to text, where you choose to speak instead of type.
- Scores each meal, and relates what you eat to how you report feeling over time.
- Detects patterns across your logs and writes the observations on your score pages.
- Drafts your daily, weekly and monthly reports.
- Reads a website self-assessment and writes the summary we email you.

### 2. How a meal score is actually produced

This is the most automatic part of the app, so it is worth setting out step by step. It is not one model inventing a number.

- The model looks at your photograph or reads your description, and identifies which foods are present and roughly how much of each.
- Each identified food is then matched against published food composition databases: the United States Department of Agriculture’s Standard Reference collection, the French food composition table CIQUAL published by ANSES, and, for branded and barcoded products, Open Food Facts.
- The nutritional figures come from those reference tables, not from the model’s own recollection. The model’s job is to say what the food is; the database supplies what is in it.
- Your macronutrients, micronutrients and meal scores are then calculated from those figures by fixed rules in our own code, not written by the model.

### 3. Where error enters, and it does

Setting the steps out makes it clear where each step can go wrong, and we would rather you knew than trusted it blindly.

The model can misidentify a food, or mistake the portion: portion estimation from a photograph is genuinely hard and is the model’s own judgement, not a measurement. The match to a reference food can select the wrong entry, for instance a raw form where you ate a cooked one. And the reference data itself has limits: the USDA and CIQUAL tables are published averages rather than facts about the particular apple you ate, while Open Food Facts is contributed by the public and its accuracy and completeness vary from one product to the next.

Errors compound along that chain. Treat every figure as an estimate with meaningful uncertainty around it, and never as a measurement.

You can correct any food or portion the app got wrong, and your correction is remembered for next time.

### 4. Where it runs, and who does not get your data

Identifying the foods in a meal photograph or description runs on OpenAI, in the United States. Everything else runs on Infomaniak’s sovereign infrastructure in Geneva, Switzerland. Both process your data strictly on our instructions, under a data processing agreement, and may not use it for their own purposes.

Apart from the meal photographs and descriptions sent to OpenAI to identify the foods, your health data is not sent to OpenAI, Google, Anthropic, Meta or any other general-purpose AI provider. It is not used to train AI models: ours, OpenAI’s, Infomaniak’s, or anyone else’s. It is not sold, and it never reaches advertisers or insurers.

### 5. What is actually sent, and the honest limits of de-identification

Before anything is sent for analysis, we detach your directly identifying information: your name, email address and contact details are not attached to what goes to the model. What is sent is the meal, the photograph, the numbers, and the check-in answers themselves.

We want to be straightforward about the limits of that, because they are real. A photograph can show your face, your hands, your kitchen or a document on the table. A free-text note or a voice recording can contain your name, a place, or a detail that identifies you. De-identification substantially reduces the risk; it does not turn your data into anonymous data.

So we do not claim your data is anonymous. We continue to treat everything sent for analysis as your personal health data, with the same protections, retention rules and rights attached to it.

### 6. What the AI is not, and where it gets things wrong

The AI produces observations, estimates and patterns. It never produces a diagnosis, a treatment, a prescription or medical advice, and nothing it writes is a clinical opinion.

It can be confidently wrong. In ordinary use it will sometimes misidentify a food, misjudge a portion, miss part of a plate it could not see, or describe a pattern that is not really there. Nutritional figures are estimates derived from images and words, not laboratory measurements, and can be materially off.

Treat every number as approximate and every observation as a prompt for your own judgement: not a conclusion, and never a reason to change medication. For anything medical, consult a qualified professional who has examined you. In an emergency, contact your local emergency services, not the app.

### 7. Human review: what is reviewed, and what is not

Written interpretations in your weekly and monthly reports are reviewed and approved by a qualified practitioner before they are released to you.

Everything else the AI produces (meal identification, portion and nutrient estimates, meal scores, pattern observations, daily report text and website assessment summaries) is generated automatically and reaches you without an individual human check. We would rather tell you that plainly than imply a level of oversight that is not there. Automatically generated material is labelled where you see it.

### 8. No automated decisions about you

FunctionAlps does not make decisions producing legal effects concerning you, or similarly significantly affecting you, within the meaning of Article 22 GDPR. It does not decide your care, your eligibility for anything, or your price.

It does profile you, in the legal sense: it analyses your data to evaluate aspects of your health and habits, and that is exactly what the scores and patterns are. Every consequential decision that follows remains yours, or your practitioner’s.

### 9. Why AI is not a separate choice

There is no manual mode. Meal analysis, your scores, your patterns and your reports are all AI-produced, so a version of FunctionAlps with AI switched off has nothing to show you.

So we do not ask you to “consent to AI” separately. That would be a fictitious choice, because refusing it would mean having no service, and a consent you cannot refuse is not one. AI is part of the description of what the service is, and the processing it performs is covered by your consent to health-data processing.

### 10. If you no longer want this processing

Withdrawing your consent to health-data processing ends this processing, AI analysis included, in Privacy & Data, in the app or on the members dashboard. Withdrawal takes effect immediately and does not affect the lawfulness of what was done beforehand.

FunctionAlps is then disabled until you consent again, or delete your account. Nothing else is taken away: your data is not deleted by withdrawing, and you can still export it or ask for it to be erased.

### 11. Questions

Anything about how the AI works, what it received, or what it produced about you: data@functionalps.ch. You have the right to an explanation of the processing, and to ask us to correct or delete what it produced.
