package com.example.productapi.service;

import com.example.productapi.dto.CreateProductRequest;
import com.example.productapi.dto.ProductResponse;
import com.example.productapi.entity.Product;
import com.example.productapi.exception.ProductNotFoundException;
import com.example.productapi.repository.ProductRepository;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class ProductService {
    private final ProductRepository productRepository;

    public ProductService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public ProductResponse createProduct(CreateProductRequest request) {

        Product product = new Product(
                null,
                request.name(),
                request.description(),
                request.price()
        );

        return toResponse(productRepository.save(product));
    }

    public List<ProductResponse> getAllProducts() {
        return productRepository.findAll()
                .stream()
                .map(this::toResponse)
                .toList();
    }

    public ProductResponse getProductById(Long id) {
        Product product = productRepository.findById(id).orElseThrow(() ->
                        new ProductNotFoundException(id));

        return toResponse(product);
    }

    public void deleteProduct(Long id) {
        boolean deleted = productRepository.deleteById(id);

        if (!deleted) {
            throw new ProductNotFoundException(id);
        }
    }

    private ProductResponse toResponse(Product product) {
        return new ProductResponse(
                product.id(),
                product.name(),
                product.description(),
                product.price()
        );
    }
}
