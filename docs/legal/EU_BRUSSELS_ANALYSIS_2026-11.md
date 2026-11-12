# What changes under EU law, and with a company in Brussels

Research of 9 November 2026, for Thomas and the legal reviewer. It follows
`EXPERT_BRIEF_2026-11.md`, which covers the texts as they stand today: a Swiss controller in
Valais.

This is a working document, not legal advice. Every rule cites its article. Rules we could
not read in an official text are marked **unverified**.

---

## 1. The short answer: how long does EU law say data must be kept?

**EU law sets no retention period for members' data.** It sets the principle, and each
country sets the numbers.

- **GDPR art. 5(1)(e):** data is kept "for no longer than is necessary for the purposes".
- **Recital 39:** "time limits should be established by the controller for erasure or for a
  periodic review".
- **Art. 13(2)(a):** the notice must give "the period … or, if that is not possible, the
  criteria". This is the rule the member's question relied on.
- **Art. 30(1)(f):** the record of processing must list the erasure deadlines.
- **Art. 17(3)(b),(e):** keeping data is lawful only to meet a legal obligation of the Union
  or a Member State, or to establish, exercise or defend legal claims.
- **Proof of consent (EDPB Guidelines 05/2020, §107):** kept while the processing lasts.
  After that, it is kept "no longer than strictly necessary for compliance with a legal
  obligation or for the establishment, exercise or defence of legal claims". The national
  limitation period therefore sets the ceiling.
- **Records, invoices and accounts are national:**
  - Directive 2011/24 art. 4(2)(f): a right to a record, with no duration.
  - VAT Directive art. 247: "Each Member State shall determine the period".
  - Directive 2013/34: no duration.
  - The Commission's 2014 study: "There are no specific rules at the EU level on the
    archiving of EHRs".

### What "European certification" (CE marking) would add

These rules cover **only the company's product documentation**, never members' data. They
apply only if FunctionAlps becomes a medical device, which it deliberately does not.

| Obligation | Applies today (not a device) | If CE-marked device software | Period |
|---|---|---|---|
| MDR art. 10(8): technical documentation, declaration of conformity, certificates, post-market and quality-system records | No | Yes | ≥ 10 years after the last unit is placed on the market |
| MDR: user or patient data | No | **No** (art. 110 refers back to the GDPR) | None |
| AI Act art. 18: documentation of a high-risk system | No | Yes, if class IIa or higher (art. 6(1)), from 2 Aug 2028 | 10 years |
| AI Act art. 19 and 26(6): logs | No | Same | ≥ 6 months |
| AI Act art. 50: transparency | Yes, since 2 Aug 2026 | Yes | No retention period |
| EHDS 2025/327 | No: micro-enterprise exemption (art. 50) and no EHR-interoperability claim | Possibly, if offered as an EHR system | 10 years for EHR-system documentation (art. 30(3)) |
| NIS2 | No: below 50 staff and €10 M | Only if medium-sized or larger | No log retention period |
| Data Act 2023/2854 | Probably not: FunctionAlps receives the data and is a small enterprise (art. 7(1)) | Same | "not … an obligation to store" (recital 20) |

**Consequence:** staying outside the MDR means no "certification" retention at all. The
retention periods come from the GDPR plus the law of the country where the company is
established, and that is where Brussels changes the numbers.

## 2. Belgian retention periods

| Element | Belgian rule | Source | Comment |
|---|---|---|---|
| Patient file | **30 years minimum, 50 years maximum** from the last contact | Loi qualité of 22.4.2019, art. 35 | Binds the **professionnel des soins de santé** (art. 2, 2°): practitioners under the coordinated law of 10.5.2015 (doctors, dietitians…), not the company. |
| The same rule for a nutrition coach or ASCA/RME therapist | **Does not apply** | Colla law of 1999 (non-conventional practices) repealed by the law of 25.11.2025 | Colla covered only osteopathy, chiropractic, acupuncture and homeopathy. Appeals against the repeal are pending at the Constitutional Court (8694, 8706). Enacted text **unverified**. |
| Accounting books and supporting documents | **7 years** from 1 January following closure (some documents 3 years) | Code of Economic Law (CDE) art. III.88 and III.86 | Not 10 years. |
| Invoices, VAT and tax records | **10 years** from 1 January following issue or closure | VAT Code art. 60 §3–4; CIR92 art. 315 (law of 20.11.2022) | Read through the IBR-IRE technical note; the article on Justel was **not read**. In practice, billing is kept 10 years. |
| Contractual limitation | **10 years** | Old Civil Code art. 2262bis §1 al. 1 (still in force) | Basis for keeping proof of consent. |
| Tort limitation | 5 years from knowledge, **20 years** absolute | Same, al. 2 and 3 | |
| Logs | **No Belgian minimum or maximum** for a private controller | Law of 30.7.2018, art. 56, which concerns only police and justice | The GDPR applies (art. 32 security; art. 5(1)(e)). Today the 12 months comes from the Swiss data protection ordinance (OPDo art. 4). |

### Proposed retention table if the controller is a Brussels company

| Element | Switzerland today (texts v10/v14) | Brussels (proposal) |
|---|---|---|
| Record of the **Valais** practitioner | 20 years after the end of follow-up (Valais Health Act art. 32) | **Unchanged.** The duty follows where she practises, not where the company is based. |
| Record of a practitioner **licensed in Belgium** (dietitian, doctor) | n/a | 30 years after the last contact, at most 50 (loi qualité art. 35). Decide before hiring one. |
| Consent history | 10 years after deletion (Code of Obligations art. 60/127) | 10 years after deletion (Civil Code art. 2262bis §1 al. 1). **Same number.** |
| Accounting | 10 years (Code of Obligations art. 958f) | Invoices and tax: 10 years (VAT Code art. 60); books: 7 years (CDE III.88). Keeping "10 years" covers both. |
| Security logs | 12 months (OPDo art. 4) | No legal period. **Keep 12 months** and justify it under GDPR art. 32 / 5(1)(e). |
| App data | While the account is active, then erased within 30 days | **Unchanged** (GDPR). |

**For the texts, the change is small.** The periods already chosen (20, 10, 10 and 12
months) stay valid. Only the legal bases cited change, and a line is added for any
practitioner licensed in Belgium.

## 3. Everything else a Brussels company changes

| Topic | Switzerland today | Brussels company | What to change in the texts |
|---|---|---|---|
| Controller | Thomas Convent, sole trader, unlimited liability | Belgian SRL (no minimum capital, financial plan, notarial deed; founders liable for 3 years if equity is manifestly insufficient, Companies Code art. 5:16, **unverified**) | Name, company number (BCE), VAT number and address in every notice. A change of controller must be announced to members (expert to decide whether health-data consent must be collected again: Q11). |
| EU lead authority | None. GDPR applies by art. 3(2), with no one-stop shop. | **APD/GBA** (Belgian authority) as lead authority (art. 56) | Privacy §21: APD for the EU, FDPIC for Switzerland. |
| EU representative | **Required** (art. 27), not yet appointed | **No longer required** | Remove the gap (precondition P5 in the brief). |
| Swiss representative | n/a | **Likely required** (Swiss data protection act art. 14: services offered at large scale and regularly, with high risk) | Name and address of the Swiss representative. |
| Data protection officer | Likely already required (GDPR art. 37(1)(c): health data at large scale as a core activity) | Same, and **notified to the APD** (art. 37(7)) | DPO contact details. Today privacy §2 says "no DPO". |
| Health-data measures | Swiss data protection act (sensitive data) | **Law of 30.7.2018 art. 9**: a list of the categories of people with access, held for the APD, and a duty of confidentiality | Internal register plus confidentiality clauses for staff and practitioners. |
| OpenAI transfer | Swiss version of the SCCs | **EU SCCs 2021/914** with the Brussels company as exporter, plus a transfer impact assessment (OpenAI is still not DPF-certified) | Privacy §12: exporter identity. EU residency (eu.api.openai.com) would remove the transfer. |
| Infomaniak (Geneva) | Transfer within Switzerland | EU→Switzerland, covered by the adequacy decision 2000/518/EC | One sentence in §12. |
| Medical devices | Outside the MDR | Same. mHealthBelgium (Belgian health-app label) requires CE marking from level M1, so it is closed to us. | None. Keep §4 of the Terms. |
| Professional titles | ASCA/RME in Valais | **"Diététicien"** is protected (LEPSS art. 73, penalty art. 127). Diagnosing or treating a "real or supposed" condition is illegal practice of medicine (art. 3, penalty art. 122). | No "diététicien" for unlicensed staff. No "thérapie", "traitement" or diagnostic wording for Belgian members. Check the website too. |
| Consumer terms | Swiss law; Lugano Convention for the EEA | CDE VI.83 black list (no exclusion for wilful misconduct or gross fault; no "inappropriate" limitation of legal rights); Brussels I bis art. 17–19 (consumers sue and are sued at home); Rome I art. 6; Swiss consumers keep Swiss law (Private International Law Act art. 120) | Rewrite the liability cap (§19) and the forum clause (§25). This was already Q6 in the brief. |
| Language | French and English | No language law found for consumer service contracts in Brussels (**unverified**). Advice: offer FR and NL. | Dutch version recommended. |
| VAT | n/a (free service) | Coaching by a non-recognised practitioner is likely at **21%**; the medical exemption is reserved for recognised professionals (VAT Code art. 44) | Prices including VAT if the service becomes paid. |

## 4. What this means in practice

1. **Nothing changes until the Brussels company exists.** The Swiss texts (v10/v14,
   pending review) remain the right ones for the current controller.
2. **The chosen periods hold up under Belgian law.** On the day of the move, the legal bases
   cited change (Belgian Civil Code instead of the Code of Obligations, VAT Code instead of
   art. 958f), not the durations.
3. **The real trap is hiring.** A Belgian-licensed dietitian or doctor brings in 30 to
   50 years of record-keeping. Agree in writing beforehand who holds those records and where.
4. **Representatives swap places.** The EU representative becomes unnecessary and a Swiss
   representative probably becomes necessary. Appoint a DPO in either case.
5. **The OpenAI transfer remains the weak point** in both scenarios (no DPF certification).
   EU residency at OpenAI solves it.

## 5. Questions to add to the expert brief

- **Q11.** On a change of controller (Swiss sole trader → Belgian SRL), is announcing it to
  members enough? Or is new explicit consent needed for health data (GDPR art. 9(2)(a))?
  The consent was given to an identified controller.
- **Q12.** Does the repeal of the Colla law withstand the pending appeals? If it were
  annulled, would the 30–50 years of the loi qualité cover the practitioners of the former
  non-conventional practices again?
- **Q13.** Where does general nutrition advice given to adults in Belgium end, and the
  illegal practice of medicine or dietetics begin (LEPSS art. 3, 71, 122, 126)? Is there
  case law?
- **Q14.** Is "large scale" (GDPR art. 37 and Swiss data protection act art. 14) already
  reached at the current number of members? If so, from what threshold do the DPO and the
  Swiss representative become mandatory?

## 6. Sources

- **GDPR:** http://data.europa.eu/eli/reg/2016/679/oj
- **EDPB Guidelines 05/2020 (consent):** https://www.edpb.europa.eu/system/files/documents/files/file1/edpb_guidelines_202005_consent_en.pdf
- **MDR 2017/745:** http://data.europa.eu/eli/reg/2017/745/oj
- **AI Act 2024/1689:** http://data.europa.eu/eli/reg/2024/1689/oj
- **Reg. 2026/1744:** http://data.europa.eu/eli/reg/2026/1744/oj
- **EHDS 2025/327:** http://data.europa.eu/eli/reg/2025/327/oj
- **Data Act 2023/2854:** http://data.europa.eu/eli/reg/2023/2854/oj
- **Directive 2011/24:** http://data.europa.eu/eli/dir/2011/24/oj
- **VAT Directive 2006/112:** http://data.europa.eu/eli/dir/2006/112/oj
- **NIS2 2022/2555:** http://data.europa.eu/eli/dir/2022/2555/oj
- **European Commission, 2014 study on national EHR laws:** https://health.ec.europa.eu/document/download/3eb04ec0-b1c3-4e01-8ffb-46765744c049_en
- **Loi qualité 22.4.2019:** https://www.ejustice.just.fgov.be/eli/loi/2019/04/22/2019041141/justel
- **Patient rights law 22.8.2002:** https://www.ejustice.just.fgov.be/eli/loi/2002/08/22/2002022737/justel
- **LEPSS 10.5.2015:** https://www.ejustice.just.fgov.be/eli/loi/2015/05/10/2015A24141/justel
- **Royal decree of 19.2.1997 (dietetics):** https://www.ejustice.just.fgov.be/eli/arrete/1997/02/19/1997022176/justel
- **Colla repeal (bill DOC 56 1076/001):** https://www.dekamer.be/FLWB/PDF/56/1076/56K1076001.pdf
- **Code of Economic Law (CDE):** https://www.ejustice.just.fgov.be/eli/loi/2013/02/28/2013A11134/justel
- **Law of 30.7.2018:** https://www.ejustice.just.fgov.be/eli/loi/2018/07/30/2018040581/justel
- **IBR-IRE technical note on retention periods (26.2.2025):** https://www.ibr-ire.be/fr/reglementation-et-publications/doctrine/notes-techniques/note-technique-detail-page/d-lai-de-conservation-des-archives
- **WP243 rev.01 (DPO guidelines):** https://ec.europa.eu/newsroom/article29/items/612048
- **mHealthBelgium:** https://mhealthbelgium.be/validation-pyramid
- **Swiss data protection act:** https://www.fedlex.admin.ch/eli/cc/2022/491/fr
- **SRL (notaire.be):** https://www.notaire.be/entreprendre/les-differentes-formes-juridiques-de-societe/la-srl-societe-responsabilite-limitee

**To confirm before drafting the Belgian texts:**
- the enacted text of the Colla repeal and its entry into force;
- VAT Code art. 60 read on Justel;
- CDE VI.82 and VI.84;
- any Brussels language rule;
- Companies Code art. 5:16.
