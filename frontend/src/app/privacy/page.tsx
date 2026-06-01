"use client";

import Link from "next/link";
import { ArrowLeft } from "lucide-react";

export default function PrivacyPage() {
  return (
    <div className="min-h-screen" style={{ background: "var(--page-bg)" }}>
      <div className="mx-auto max-w-3xl px-4 sm:px-6 py-16">
        <Link
          href="/"
          className="inline-flex items-center gap-1 text-sm text-[var(--muted-text)] hover:text-[var(--body-text)] transition-colors mb-8"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to home
        </Link>

        <h1 className="text-3xl font-bold text-[var(--body-text)] mb-2">
          Privacy Policy
        </h1>
        <p className="text-sm text-[var(--muted-text)] mb-10">
          Last updated: May 30, 2026
        </p>

        <div className="space-y-8 text-[var(--body-text)] text-base leading-relaxed">
          {/* 1. Who We Are */}
          <section>
            <h2 className="text-xl font-semibold mb-3">1. Who We Are</h2>
            <p>
              AiFlowHub is an API aggregation platform for AI models, operated by a
              solo developer. Our servers are hosted in Germany (Hetzner). This privacy
              policy explains what data we collect, why we collect it, and what rights
              you have over your information.
            </p>
            <p className="mt-2">
              We are committed to protecting your privacy and handling your data
              transparently. If you are in the European Economic Area (EEA) or the UK,
              the General Data Protection Regulation (GDPR) applies to how we process
              your personal data.
            </p>
          </section>

          {/* 2. What We Collect */}
          <section>
            <h2 className="text-xl font-semibold mb-3">2. What Data We Collect</h2>
            <p>We collect only the data necessary to provide and improve our service:</p>
            <ul className="list-disc pl-6 mt-2 space-y-1 text-[var(--muted-text)]">
              <li>
                <strong>Account information:</strong> email address, display name, and
                account password (hashed and salted — we never store plain-text passwords).
              </li>
              <li>
                <strong>Payment records:</strong> transaction IDs, amounts, and dates from
                NOWPayments. We do not store cryptocurrency wallet addresses or any
                sensitive financial details.
              </li>
              <li>
                <strong>API usage logs:</strong> timestamps, model names, request sizes,
                token counts, error codes, and response times. These help us with
                billing, debugging, and service improvement.
              </li>
              <li>
                <strong>Technical data:</strong> IP address, browser/user-agent string,
                and session information when you use the web interface.
              </li>
            </ul>
          </section>

          {/* 3. What We Do NOT Collect */}
          <section>
            <h2 className="text-xl font-semibold mb-3">3. What We Do NOT Collect</h2>
            <p>
              We do <strong>not</strong> read, store, or log the content of your API
              requests (prompts) or the responses from the model providers. The content
              you send through the API passes through our system briefly for routing, but
              is not retained.
            </p>
            <p className="mt-2">
              We do not track your activity across other websites, sell your data, or use
              third-party advertising trackers.
            </p>
          </section>

          {/* 4. How We Use Your Data */}
          <section>
            <h2 className="text-xl font-semibold mb-3">4. How We Use Your Data</h2>
            <p>We use your data for the following purposes:</p>
            <ul className="list-disc pl-6 mt-2 space-y-1 text-[var(--muted-text)]">
              <li>To create and manage your account.</li>
              <li>To process payments and track your credit balance.</li>
              <li>To operate, monitor, and troubleshoot the API service.</li>
              <li>To communicate with you about your account, billing, or service changes.</li>
              <li>To improve the platform's performance, reliability, and user experience.</li>
            </ul>
            <p className="mt-2">
              We do not use your data for automated decision-making or profiling.
            </p>
          </section>

          {/* 5. Data Storage & Security */}
          <section>
            <h2 className="text-xl font-semibold mb-3">5. Data Storage &amp; Security</h2>
            <p>
              All data is stored on servers hosted by Hetzner in Germany. We use industry-standard
              encryption (TLS) for data in transit and encryption at rest for sensitive data.
              Passwords are hashed using a strong, salted algorithm.
            </p>
            <p className="mt-2">
              While we take reasonable measures to protect your data, no internet-based service
              can guarantee absolute security. We encourage you to use strong, unique passwords
              and keep your API keys confidential.
            </p>
          </section>

          {/* 6. Cookies */}
          <section>
            <h2 className="text-xl font-semibold mb-3">6. Cookies</h2>
            <p>
              We use minimal cookies and local storage only for essential functionality:
              session management (keeping you logged in), and remembering your theme preference
              (light/dark mode). We do not use tracking cookies, advertising cookies, or any
              third-party cookies.
            </p>
            <p className="mt-2">
              You can disable cookies in your browser settings, but some parts of the platform
              may not function correctly without them.
            </p>
          </section>

          {/* 7. Data Sharing */}
          <section>
            <h2 className="text-xl font-semibold mb-3">7. Data Sharing</h2>
            <p>
              We do not sell, rent, or share your personal data with third parties for their
              own purposes. We may share data in the following limited circumstances:
            </p>
            <ul className="list-disc pl-6 mt-2 space-y-1 text-[var(--muted-text)]">
              <li>
                <strong>NOWPayments:</strong> When you make a payment, certain transaction
                details are shared with NOWPayments to process the payment. Their privacy
                policy applies to that interaction.
              </li>
              <li>
                <strong>Legal obligations:</strong> If required by law, court order, or
                valid legal process, we may disclose data to authorities.
              </li>
              <li>
                <strong>Service providers:</strong> We use Hetzner (hosting) and potentially
                email delivery services. These providers process data only on our instructions
                and are contractually bound to protect it.
              </li>
            </ul>
          </section>

          {/* 8. Data Retention */}
          <section>
            <h2 className="text-xl font-semibold mb-3">8. Data Retention</h2>
            <p>
              We retain your account data for as long as your account is active. API usage
              logs are retained for up to 12 months for billing and debugging purposes, then
              anonymized or deleted.
            </p>
            <p className="mt-2">
              If you delete your account, we will remove your personal data within 30 days,
              except where we are legally required to retain certain records (e.g., for tax
              purposes, payment records may be kept for up to 10 years as required by German law).
            </p>
          </section>

          {/* 9. Your Rights (GDPR) */}
          <section>
            <h2 className="text-xl font-semibold mb-3">9. Your Rights</h2>
            <p>
              Under the GDPR, you have the following rights regarding your personal data:
            </p>
            <ul className="list-disc pl-6 mt-2 space-y-1 text-[var(--muted-text)]">
              <li><strong>Access:</strong> Request a copy of the data we hold about you.</li>
              <li><strong>Rectification:</strong> Correct inaccurate or incomplete data.</li>
              <li><strong>Deletion:</strong> Request deletion of your data (subject to legal retention obligations).</li>
              <li><strong>Restriction:</strong> Limit how we process your data in certain circumstances.</li>
              <li><strong>Portability:</strong> Receive your data in a structured, machine-readable format.</li>
              <li><strong>Objection:</strong> Object to processing based on legitimate interests.</li>
            </ul>
            <p className="mt-2">
              To exercise any of these rights, contact us at the email address below. We will
              respond within 30 days. You also have the right to lodge a complaint with your
              local data protection authority.
            </p>
          </section>

          {/* 10. Legal Basis for Processing (GDPR) */}
          <section>
            <h2 className="text-xl font-semibold mb-3">10. Legal Basis for Processing</h2>
            <p>
              Under the GDPR, we process your data based on the following legal grounds:
            </p>
            <ul className="list-disc pl-6 mt-2 space-y-1 text-[var(--muted-text)]">
              <li>
                <strong>Performance of a contract:</strong> Account creation, payment processing,
                and API service delivery are necessary to fulfill our agreement with you.
              </li>
              <li>
                <strong>Legitimate interests:</strong> Usage logs for service improvement,
                security monitoring, and fraud prevention.
              </li>
              <li>
                <strong>Legal obligations:</strong> Retention of payment records for tax and
                regulatory compliance.
              </li>
              <li>
                <strong>Consent:</strong> Where required, we will ask for your consent before
                processing data for specific purposes.
              </li>
            </ul>
          </section>

          {/* 11. International Transfers */}
          <section>
            <h2 className="text-xl font-semibold mb-3">11. International Transfers</h2>
            <p>
              Our servers are located in Germany. If you access AiFlowHub from outside the
              European Economic Area, your data may be transferred to and processed in Germany.
              We ensure appropriate safeguards are in place for such transfers.
            </p>
          </section>

          {/* 12. Changes */}
          <section>
            <h2 className="text-xl font-semibold mb-3">12. Changes to This Policy</h2>
            <p>
              We may update this privacy policy from time to time. Significant changes will be
              communicated through the platform or via email. The "Last updated" date at the top
              of this page will reflect the most recent revision.
            </p>
          </section>

          {/* Contact */}
          <section>
            <h2 className="text-xl font-semibold mb-3">Contact Us</h2>
            <p>
              If you have any questions about this privacy policy or wish to exercise your data
              rights, please contact us at:
            </p>
            <p className="mt-2 text-[var(--muted-text)]">
              Email: privacy@aiflowhub.com
            </p>
          </section>
        </div>
      </div>
    </div>
  );
}
