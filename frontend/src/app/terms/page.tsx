"use client";

import Link from "next/link";
import { ArrowLeft } from "lucide-react";

export default function TermsPage() {
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
          Terms of Service
        </h1>
        <p className="text-sm text-[var(--muted-text)] mb-10">
          Last updated: May 30, 2026
        </p>

        <div className="space-y-8 text-[var(--body-text)] text-base leading-relaxed">
          {/* 1. Service Description */}
          <section>
            <h2 className="text-xl font-semibold mb-3">1. What AiFlowHub Is</h2>
            <p>
              AiFlowHub is an API aggregation platform that provides developers with a single,
              OpenAI-compatible endpoint to access large language models from Chinese providers
              including DeepSeek, GLM, Qwen, MiniMax, and others.
            </p>
            <p className="mt-2">
              We pass your requests through to underlying model providers. We do not inspect,
              moderate, filter, or modify the content of your API requests or responses beyond what
              is technically necessary to route them.
            </p>
          </section>

          {/* 2. User Responsibilities */}
          <section>
            <h2 className="text-xl font-semibold mb-3">2. Your Responsibilities</h2>
            <p>
              You agree to use AiFlowHub in compliance with all applicable laws and regulations.
              You must not use the service for any illegal activity, or in a way that generates
              excessive load, disrupts the platform, or harms other users.
            </p>
            <p className="mt-2">
              You are responsible for the content you send through the API. While we do not
              moderate content, each underlying model provider has its own usage policies, and
              violations may result in that provider blocking your access.
            </p>
          </section>

          {/* 3. Prohibited Conduct */}
          <section>
            <h2 className="text-xl font-semibold mb-3">3. Prohibited Conduct</h2>
            <p>You may not:</p>
            <ul className="list-disc pl-6 mt-2 space-y-1 text-[var(--muted-text)]">
              <li>Use AiFlowHub in violation of any applicable law or regulation.</li>
              <li>Attempt to reverse-engineer, bypass rate limits, or scrape the platform.</li>
              <li>Submit requests that contain malware, phishing attempts, or harmful code.</li>
              <li>Impersonate any person or entity, or misrepresent your affiliation.</li>
              <li>Use the service in a way that could overload or degrade the experience for other users.</li>
            </ul>
          </section>

          {/* 4. Payment Terms */}
          <section>
            <h2 className="text-xl font-semibold mb-3">4. Payment Terms</h2>
            <p>
              AiFlowHub accepts payments in USDT (cryptocurrency) through NOWPayments. You
              purchase credits which are added to your account balance, and API usage is deducted
              from this balance based on the pricing displayed on our Pricing page.
            </p>
            <p className="mt-2">
              <strong>All payments are final and non-refundable.</strong> Credits do not expire
              as long as your account remains active. If you choose to close your account, any
              remaining balance will be forfeited. We reserve the right to adjust pricing with
              reasonable notice.
            </p>
          </section>

          {/* 5. Service Availability */}
          <section>
            <h2 className="text-xl font-semibold mb-3">5. Service Availability</h2>
            <p>
              We strive to keep AiFlowHub operational and reliable, but we do not guarantee 100%
              uptime. The platform may experience interruptions due to upstream provider outages,
              maintenance, or unforeseen issues.
            </p>
            <p className="mt-2">
              We are a small team operating with a lightweight infrastructure. While we work hard
              to minimize downtime, the service is provided &ldquo;as is&rdquo; and &ldquo;as
              available.&rdquo;
            </p>
          </section>

          {/* 6. Liability */}
          <section>
            <h2 className="text-xl font-semibold mb-3">6. Limitation of Liability</h2>
            <p>
              AiFlowHub is operated by a single-developer team. To the maximum extent permitted
              by applicable law, we shall not be liable for any indirect, incidental, special,
              consequential, or punitive damages arising from your use of the service.
            </p>
            <p className="mt-2">
              This includes, but is not limited to, loss of data, loss of business, service
              interruptions, or any issues caused by upstream model providers. Our total
              liability, if any, is limited to the amount you have paid us in the 12 months
              preceding the claim.
            </p>
          </section>

          {/* 7. Account Management */}
          <section>
            <h2 className="text-xl font-semibold mb-3">7. Accounts</h2>
            <p>
              When you register, you agree to provide accurate information and keep your API keys
              and account credentials secure. You are responsible for all activity that occurs
              under your account.
            </p>
            <p className="mt-2">
              We reserve the right to suspend or terminate any account at our discretion—for
              example, if we detect abusive usage, suspected fraud, or violation of these terms.
              If your account is terminated for violation of these terms, remaining credits will
              be forfeited.
            </p>
          </section>

          {/* 8. Intellectual Property */}
          <section>
            <h2 className="text-xl font-semibold mb-3">8. Intellectual Property</h2>
            <p>
              The AiFlowHub brand, name, logo, website design, and platform software are our
              intellectual property. You may not reproduce, distribute, or create derivative works
              without our permission.
            </p>
            <p className="mt-2">
              You retain all rights to the content you send and receive through the API. We do not
              claim ownership of your data, prompts, or model outputs.
            </p>
          </section>

          {/* 9. Changes */}
          <section>
            <h2 className="text-xl font-semibold mb-3">9. Changes to These Terms</h2>
            <p>
              We may update these Terms of Service from time to time. Significant changes will be
              communicated through the platform (e.g., via email or a notice on the dashboard).
              Continued use of AiFlowHub after changes take effect constitutes your acceptance of
              the updated terms.
            </p>
          </section>

          {/* 10. Governing Law */}
          <section>
            <h2 className="text-xl font-semibold mb-3">10. Governing Law</h2>
            <p>
              These terms are governed by the laws of the Federal Republic of Germany, where our
              servers are located. Any disputes shall be resolved in the courts of Berlin, Germany.
            </p>
            <p className="mt-2">
              If any provision of these terms is found to be unenforceable, the remaining
              provisions will remain in full effect.
            </p>
          </section>

          {/* Contact */}
          <section>
            <h2 className="text-xl font-semibold mb-3">Contact</h2>
            <p>
              If you have questions about these terms, please reach out via the contact
              information listed on our website or through the in-app support channel.
            </p>
          </section>
        </div>
      </div>
    </div>
  );
}
