# Contributing

This project welcomes contributions and suggestions. Most contributions require you to
agree to a Contributor License Agreement (CLA) declaring that you have the right to,
and actually do, grant us the rights to use your contribution. For details, visit
https://cla.microsoft.com.

When you submit a pull request, a CLA-bot will automatically determine whether you need
to provide a CLA and decorate the PR appropriately (e.g., label, comment). Simply follow the
instructions provided by the bot. You will only need to do this once across all repositories using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/)
or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## GitHub Pages changes

Run `make test` with Node.js 22 or later, then `make` to build the site.
Preview it with `python3 -m http.server 8000 --bind 127.0.0.1 --directory _site`
and open http://127.0.0.1:8000/index.html#prerequisites.

Check Java Challenge 00: its PhotoAlbum VM deployment link should open the
[infrastructure guide](Student/Resources/java/infra/README.md) in the same Pages
drawer, including its screenshot and a working back link, while
the general-prerequisites link should return to the site's prerequisites section.
The build publishes only the guide and its screenshot, not the Terraform files.
Known challenge, solution, and resource links open in the drawer; other Markdown documents
and links with document fragments open on GitHub. Relative Markdown links are
resolved against their source document, not the hosting page.