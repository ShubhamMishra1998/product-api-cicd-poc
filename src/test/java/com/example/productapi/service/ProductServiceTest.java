package com.example.productapi.service;

import com.example.productapi.dto.CreateProductRequest;
import com.example.productapi.dto.ProductResponse;
import com.example.productapi.entity.Product;
import com.example.productapi.exception.ProductNotFoundException;
import com.example.productapi.repository.ProductRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
@ExtendWith(MockitoExtension.class)
class ProductServiceTest {
    @Mock
    private ProductRepository productRepository;
    @InjectMocks
    private ProductService productService;

    @Test
    void shouldCreateProduct() {
        CreateProductRequest request = new CreateProductRequest(
                "Laptop", "Gaming laptop", new BigDecimal("75000")
        );

        when(productRepository.save(any(Product.class)))
                .thenAnswer(invocation -> {
                    Product product = invocation.getArgument(0);
                    return new Product(1L, product.name(),
                            product.description(), product.price());
                });

        ProductResponse response = productService.createProduct(request);

        assertEquals(1L, response.id());
        assertEquals("Laptop", response.name());
        assertEquals(new BigDecimal("75000"), response.price());

        verify(productRepository).save(any(Product.class));
    }

    @Test
    void shouldReturnAllProducts() {
        when(productRepository.findAll()).thenReturn(List.of(
                new Product(1L, "Laptop", "Gaming laptop",
                        new BigDecimal("75000"))
        ));

        List<ProductResponse> products = productService.getAllProducts();

        assertEquals(1, products.size());
        assertEquals("Laptop", products.get(0).name());
    }

    @Test
    void shouldReturnProductById() {
        Product product = new Product(
                1L, "Laptop", "Gaming laptop",
                new BigDecimal("75000")
        );

        when(productRepository.findById(1L)).thenReturn(Optional.of(product));

        ProductResponse response = productService.getProductById(1L);

        assertEquals(1L, response.id());
        assertEquals("Laptop", response.name());
    }

    @Test
    void shouldThrowExceptionWhenProductNotFound() {
        when(productRepository.findById(99L))
                .thenReturn(Optional.empty());

        assertThrows(ProductNotFoundException.class, () -> productService.getProductById(99L));
    }

    @Test
    void shouldDeleteProduct() {
        when(productRepository.deleteById(1L)).thenReturn(true);

        assertDoesNotThrow(() -> productService.deleteProduct(1L));

        verify(productRepository).deleteById(1L);
    }

    @Test
    void shouldThrowExceptionWhenDeletingMissingProduct() {
        when(productRepository.deleteById(99L)).thenReturn(false);

        assertThrows(
                ProductNotFoundException.class,
                () -> productService.deleteProduct(99L)
        );
    }

}