# Reports

This folder is where HTTMELY's local report workflow writes generated HTML and Markdown.

Generated report files are intentionally not part of the public repository because they can include machine-local paths, app inventories, folder names, and other private context.

To generate reports locally:

```bash
make refresh
```

The viewer can also open any other folder of `.html`, `.htm`, `.md`, or `.markdown` files through `Places > Add Folder...`.
