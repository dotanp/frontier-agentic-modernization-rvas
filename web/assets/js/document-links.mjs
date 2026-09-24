const repositoryUrl = 'https://github.com/microsoft/frontier-agentic-modernization-rvas/blob/main/';

export function resolveDocumentLink(href, sourceFile, pageUrl, documents) {
    if (!href || /^(?:[a-z][a-z0-9+.-]*:|\/\/|#)/i.test(href)) return null;

    const sourceUrl = new URL(sourceFile, 'https://repository.invalid/');
    const resolved = new URL(href, sourceUrl);
    if (!resolved.pathname.endsWith('.md')) return null;

    const file = resolved.pathname.slice(1);
    if (file === 'README.md' && resolved.hash === '#prerequisites') {
        const target = new URL(pageUrl);
        target.search = resolved.search;
        target.hash = resolved.hash;
        return { href: target.href, section: 'prerequisites' };
    }

    const target = { href: repositoryUrl + file + resolved.search + resolved.hash };
    // Other fragments use GitHub's rendered headings rather than an unanchored drawer.
    if (documents.includes(file) && !resolved.hash && !resolved.search) target.file = file;
    return target;
}
