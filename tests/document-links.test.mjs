import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { RESOURCE_FILES, resolveDocumentLink } from '../web/assets/js/document-links.mjs';

const pageUrl = 'https://microsoft.github.io/frontier-agentic-modernization-rvas/index.html#prerequisites';
const repositoryUrl = 'https://github.com/microsoft/frontier-agentic-modernization-rvas/blob/main/';
const documents = [
    'README.md', 'Student/java/Challenge-00.md', 'Student/java/Challenge-01.md', 'Coach/java/Solution-00.md',
    ...RESOURCE_FILES.map(entry => entry.file),
];
const resolve = (href, source = 'Student/java/Challenge-00.md', page = pageUrl) =>
    resolveDocumentLink(href, source, page, documents);

test('the actual PhotoAlbum deployment link opens the infrastructure README in the Pages drawer', () => {
    const challenge = readFileSync(new URL('../Student/java/Challenge-00.md', import.meta.url), 'utf8');
    const href = challenge.match(/\]\(([^)]*Resources\/java\/infra\/README\.md)\)/)[1];
    assert.deepEqual(resolve(href), {
        href: `${repositoryUrl}Student/Resources/java/infra/README.md`,
        file: 'Student/Resources/java/infra/README.md',
    });
});

test('the deployment guide links back to Java prerequisites in the drawer', () => {
    const source = 'Student/Resources/java/infra/README.md';
    const guide = readFileSync(new URL(`../${source}`, import.meta.url), 'utf8');
    const href = guide.match(/\[Back to Java prerequisites\]\(([^)]+)\)/)[1];
    assert.deepEqual(resolve(href, source), {
        href: `${repositoryUrl}Student/java/Challenge-00.md`,
        file: 'Student/java/Challenge-00.md',
    });
});

test('prerequisite links from each track stay on GitHub Pages', () => {
    for (const track of ['java', 'dotnet', 'net8']) {
        const source = `Student/${track}/Challenge-00.md`;
        const challenge = readFileSync(new URL(`../${source}`, import.meta.url), 'utf8');
        const href = challenge.match(/\[Prerequisites\]\(([^)]+)\)/)[1];
        assert.deepEqual(resolve(href, source), { href: pageUrl, section: 'prerequisites' });
    }
});

test('prerequisites retain the hosting prefix on a local or forked site', () => {
    assert.deepEqual(resolve('../../README.md#prerequisites', undefined, 'http://localhost:8080/custom-site/index.html'), {
        href: 'http://localhost:8080/custom-site/index.html#prerequisites',
        section: 'prerequisites',
    });
});

test('known documents retain drawer navigation and a usable new-tab URL', () => {
    for (const [href, source, file] of [
        ['./Challenge-01.md', 'Student/java/Challenge-00.md', 'Student/java/Challenge-01.md'],
        ['../../README.md', 'Student/java/Challenge-00.md', 'README.md'],
        ['Student/java/Challenge-00.md', 'README.md', 'Student/java/Challenge-00.md'],
        ['../../Coach/java/Solution-00.md', 'Student/java/Challenge-00.md', 'Coach/java/Solution-00.md'],
    ]) {
        assert.deepEqual(resolve(href, source), { href: repositoryUrl + file, file });
    }
});

test('documents outside the drawer fall back to their own GitHub path', () => {
    assert.deepEqual(resolve('../../Coach/README.md'), { href: `${repositoryUrl}Coach/README.md` });
});

test('fragments and queries are preserved on GitHub where Markdown anchors are rendered', () => {
    for (const href of [
        '../Resources/java/infra/README.md?plain=1#deployment',
        './Challenge-01.md#success-criteria',
        '../../README.md#learning-objectives',
    ]) {
        const path = new URL(href, 'https://repository.invalid/Student/java/Challenge-00.md');
        assert.deepEqual(resolve(href), { href: repositoryUrl + path.pathname.slice(1) + path.search + path.hash });
    }
});

test('external URLs, page anchors, and non-Markdown links are not treated as repository documents', () => {
    for (const href of [
        'https://example.com/README.md',
        'http://example.com/README.md#section',
        '//example.com/README.md',
        'mailto:maintainer@example.com',
        '#prerequisites',
        'https://example.com/',
        './diagram.png',
        '',
        null,
    ]) {
        assert.equal(resolve(href), null, String(href));
    }
});
